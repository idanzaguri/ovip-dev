# Running the OVIP bundles on EDA Playground through Claude in Chrome

VCS and Xcelium are not installed locally. EDA Playground (edaplayground.com)
runs both; the user's account is approved for the commercial simulators. This
is the procedure that worked on 2026-10-26 (VCS 2025.06, Xcelium 25.03). It
drives the site through the `mcp__claude-in-chrome__*` tools; load the
`claude-in-chrome` skill first.

## Pieces

| Piece | Role |
|---|---|
| `tools/bundle_for_eda.py` | flattens a VIP into `eda_tb.sv` + `eda_00_top.sv` + body chunks under 100 KB |
| `scripts/eda_server.py` | serves `eda_bundle/` on `http://127.0.0.1:8765` with CORS; stores POSTed logs |
| `scripts/eda_runner.js` | injected into the page: sets the options, swaps `TEST_NAME`, clicks Run, waits, posts the log |
| `scripts/eda_summary.py` | one line per stored log: UVM counts, compile errors, unknown warnings, verdict |

The bundles to run, and what each one proves:

| Bundle | Top | Runs | Proves |
|---|---|---|---|
| `all` | generated `tb` | 1 per simulator | the whole family compiles and elaborates together |
| `apb`, `axi_stream`, `axi` | the VIP's testbench | every test per simulator | the test suites pass |
| `ace` | `examples/ovip_ace/01_coherent_loopback` | 1 per simulator | the ACE example runs (no testbench yet) |

## Step by step

1. Generate the bundles and start the server:
   ```sh
   for v in all apb axi axi_stream ace; do python3 tools/bundle_for_eda.py --vip $v --out eda_bundle/$v --clean; done
   python3 tools/compile_check.py --stages eda          # Questa compiles every bundle first
   nohup python3 .claude/skills/release/scripts/eda_server.py > sim/eda_playground/server.log 2>&1 &
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8765/apb/eda_tb.sv   # expect 200
   ```
2. Open `https://www.edaplayground.com/` in a new tab (`tabs_create_mcp`, then
   `navigate`). If the login dialog shows, stop and ask the user to log in: it
   has a reCAPTCHA, and logging in is theirs to do. Logged in means the top
   bar shows "Profile" and `document.getElementById('btn-logout')` exists.
3. Inject `scripts/eda_runner.js`: read the file and pass its whole text to
   `javascript_tool`. It returns "ovip runner installed; logged in: true".
4. `await __ovip.setup('<bundle>')` (javascript_tool). It selects UVM 1.2 and
   VCS, appends `-debug_access+all` to the VCS compile options, and puts the
   bundle's `eda_tb.sv` into the `testbench.sv` pane. The first fetch to
   127.0.0.1 can hang for up to 45 s while Chrome asks for local-network
   access; if the call times out, wait and call `setup` again.
5. Upload the bundle's other `eda_*.sv` files. Playground only takes uploads
   through its "New File" dialog:
   - click the "+" right of the `testbench.sv` tab (about x 247, y 51 at
     1512 px width; take a screenshot if unsure). The dialog is in-page, not
     a native prompt.
   - `find` "all file inputs (type=file) on the page". Two show up: the
     testbench one and the design one. Use the **testbench** one, which has
     the lower ref number. The tool cannot upload from a folder dialog, and a
     wrong ref lands the files in `#designFileupload` where nothing happens.
   - `file_upload` with that ref and the absolute paths of every file in
     `eda_bundle/<bundle>/` except `eda_tb.sv`.
   - check `__ovip.tabs()`: every uploaded name must be a tab. If the list is
     only `testbench.sv`, the files went to the design input: run
     `document.getElementById('designFileupload').value = ''` and upload again
     with the other ref, dialog still open.
6. Start: `__ovip.start(__ovip.tests(), ['vcs', 'xcelium'])`. For `all` and
   `ace` there is no `TEST_NAME`, so `tests()` is empty and one run per
   simulator happens. The runner swaps the active `TEST_NAME` define, clicks
   Run, waits for the last log line `Done`, posts the log, and moves on.
7. Poll with `await __ovip.sleep(40000); __ovip.status()` (the tool's own
   limit is 45 s). `bad` lists runs with errors, fatals, compile errors or
   an interrupted run; `running: false` means the list is done. Rates seen:
   VCS 25 to 40 s per test, Xcelium 14 to 17 s, so the 53 AXI tests take
   about 50 min for both simulators.
8. Next bundle: `__ovip.go()` loads a fresh playground (it clears the site's
   unsaved-changes guard first; `navigate` is refused by that guard). Wait
   5 s, then repeat from step 3.
9. When all bundles are done: `python3 .claude/skills/release/scripts/eda_summary.py --warnings`.
   Close the tab with `tabs_close_mcp` and stop the server with `fuser -k 8765/tcp`.

## Known noise, not failures

- VCS: `Warning-[TLRCE] Too large repetition count expression` on
  `repeat (size) bytes.push_back($urandom)` in `ovip_mem.sv` (`size` is
  64-bit). Present in every run since before v0.4.0.
- Xcelium: `xmsim: *W,PRPASZ` on `uvm_string_to_bits` / `uvm_bits_to_string`,
  a probe-size notice from the Playground's run setup.
- `ovip_mem_test` ends with "Execution interrupted or reached maximum
  runtime": its write_bytestream benchmark exceeds the Playground cap. The user
  declined to split the benchmark out; do not propose it again.
- The Playground sometimes loses a job: the log ends with "This process
  not found on server." and no `Done` line. The runner clicks Run again,
  up to three attempts; a log that still ends that way is a lost run, not
  a failure of the test. Re-run it by hand with `__ovip.runOne(name, tag)`.
- The `all` bundle prints no UVM report summary; its pass line is
  `OVIP: compiled and elaborated ovip_axi, ovip_ace, ovip_apb, ovip_axi_stream`.

## Page facts (verified 2026-10-26)

- Editors are CodeMirror. `document.querySelectorAll('.CodeMirror')[0].CodeMirror`
  is `testbench.sv`; uploaded files get their own instances after it.
- Selects: `#methodologyLibrary` (UVM 1.2 is value `701`), `#simulator`
  (`1301` Synopsys VCS 2025.06, `1501` Cadence Xcelium 25.03, `1701` Siemens
  Questa 2025.2). Values can change when the site upgrades a simulator:
  `__ovip.simOptions()` lists the current ones.
- Compile options: `#vcsCompileOptions` default
  `-timescale=1ns/1ns +vcs+flush+all +warn=all -sverilog`. Without
  `-debug_access+all`, `uvm_hdl_force` reports "unable to write to hdl path"
  and the mid-test reset tests end in a UVM_FATAL. Xcelium's defaults
  (`-timescale 1ns/1ns -sysv`, run `-access +rw`) need nothing.
- Run button: `#runButton`. The Log pane is cleared when a run starts and its
  last line is `Done` when the run ends.
- The `javascript_tool` replaces any returned string that contains `=` with
  `[BLOCKED: Cookie/query string data]`. `__ovip.san()` swaps `=` for `≡`.
- Playground compiles only `design.sv` and `testbench.sv`; uploads are there
  to be `include`d, which is why the file names must stay exactly as
  generated.
- Uploading through the `#testbenchFileupload` input takes effect only while
  the "New File" dialog is open.

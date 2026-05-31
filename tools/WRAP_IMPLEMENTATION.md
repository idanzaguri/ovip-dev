# Implementing WRAP Burst Support in ovip_axi

A working guide for adding `OVIP_AXI_BURST_WRAP` support. WRAP is currently a
hard `uvm_fatal` in several places; this document explains the AXI semantics and
lists **every** spot that must change, by file + function (referenced by `grep`
string so it survives line-number drift).

---

## 1. WRAP semantics (AXI recap)

WRAP behaves like INCR (the address advances by the transfer size each beat)
**except** the address wraps back to a lower boundary once it reaches the top of
a fixed-size window. It's the burst type used for **cache-line fills**, where the
critical word is fetched first and the rest of the line follows, wrapping around.

**Constraints (must be checked):**
- **Burst length** must be **2, 4, 8, or 16** beats (`AxLEN ∈ {1,3,7,15}`).
- **Start address** must be **aligned to the transfer size** (`AxADDR % 2^AxSIZE == 0`).
- A WRAP burst therefore **cannot cross a 4 KiB boundary** (the wrap window is
  aligned and bounded), so no extra 4K check is needed for WRAP.

**Address math** (let `Nbytes = 2^AxSIZE`, `Len = AxLEN+1`, `Total = Nbytes*Len`):
```
Wrap_Lower   = (Start_Address / Total) * Total      // align Start down to Total
Wrap_Upper   = Wrap_Lower + Total
Address(0)   = Start_Address                         // size-aligned
Address(n)   = Wrap_Lower + ((Start_Address - Wrap_Lower + n*Nbytes) % Total)
```
i.e. addresses step by `Nbytes`; when they would reach `Wrap_Upper` they wrap to
`Wrap_Lower`. The **byte lane** a beat occupies on the data bus is
`Address(n) % bus_width_bytes` (same rule as INCR — only the address sequence
differs).

Worked example: `Start=0x34`, `Nbytes=4`, `Len=4` → `Total=16`,
`Wrap_Lower=0x30`, addresses `0x34, 0x38, 0x3C, 0x30` (wraps after the 3rd beat).

---

## 2. Where WRAP is blocked today

| Location (grep) | Current behavior |
|---|---|
| `ovip_axi_monitor.sv` (grep `need to implement transaction check for WRAP`) | `uvm_fatal` in `check_address_phase` |
| `ovip_axi_trans.sv` (grep `calculate_transfer_starting_byte_lane: OVIP_AXI_BURST_WRAP`) | `uvm_fatal` in `calculate_transfer_starting_byte_lane` |
| `ovip_axi_trans.sv` (grep `check_strb: OVIP_AXI_BURST_WRAP`) | `uvm_fatal` in `check_strb` |
| `ovip_axi_trans.sv` (grep `Only INCR burst type is supported`) | `uvm_fatal_context` in `reshape_axi_transaction` |
| `ovip_axi_base_slave_sequence.sv` (grep `populate_data_from_mem: OVIP_AXI_BURST_WRAP`) | `uvm_fatal` in `populate_data_from_mem` |
| `ovip_axi_base_slave_sequence.sv` (`write_transaction_to_mem`) | falls through silently — only INCR/FIXED handled |

---

## 3. Files & functions to modify

### 3.1 `src/ovip_axi_trans.sv` — the core, do this first

This is where the per-beat address→byte-lane mapping lives; the drivers, monitor
and slave sequence all rely on it, so fixing it unblocks most of the rest.

- **`calculate_transfer_starting_byte_lane`** (grep `function void calculate_transfer_starting_byte_lane`):
  remove the WRAP `uvm_fatal` and fill `transfer_starting_byte_lane[ii]` for WRAP.
  The INCR loop increments `byte_lane_offset` by `burst_size` and wraps at
  `bus_width`. For WRAP you additionally wrap the **address** at the wrap window:
  compute `Total = (len+1)*burst_size` and `Wrap_Lower = (addr/Total)*Total`, then
  for each beat use `Address(ii)` from §1 and set the lane to
  `Address(ii) % bus_width`. Note WRAP is always treated as a narrow-ish transfer
  for lane purposes (per-beat lanes differ), so don't early-return on
  `!is_narrow_transfer` for WRAP.
- **`check_strb`** (grep `virtual function bit check_strb`): remove the WRAP
  `uvm_fatal` and compute the active-byte mask per beat the same way as INCR, but
  using the wrapped per-beat byte lane from above (`transfer_starting_byte_lane[ii]`).
  The mask logic itself is identical once the starting lane is correct.
- **`reshape_axi_transaction`** (grep `Only INCR burst type is supported`): this
  static helper reshapes data between the AXI transaction and the memory-shaped
  transaction (used by the slave responder). It currently fatals on non-INCR. For
  WRAP you must walk source/destination byte offsets following the **wrapping**
  address sequence instead of the monotonic INCR one. Easiest path: convert the
  WRAP beat order into linear memory order before reshaping (un-wrap), or special-
  case the address stepping. Consider whether you'd rather **not** reshape WRAP at
  all and instead handle it directly in the slave sequence (see 3.3).

### 3.2 `src/ovip_axi_monitor.sv` — `check_address_phase`

- Remove the `uvm_fatal` (grep `need to implement transaction check for WRAP`).
  The WRAP checks are **already written** right below it (start-address alignment,
  length ∈ {2,4,8,16}) — they're just dead code behind the fatal. Un-dead-code them.
- No 4K-cross check is needed for WRAP (§1).
- Data reconstruction (`sample_write_data` / `sample_read_data`) already shifts by
  `transfer_starting_byte_lane[...]`, so it works automatically once 3.1 is done —
  but verify the per-beat lane is what the monitor expects for wrapped addresses.

### 3.3 `src/seq/ovip_axi_base_slave_sequence.sv` — the responder model

- **`populate_data_from_mem`** (grep `populate_data_from_mem: OVIP_AXI_BURST_WRAP`):
  remove the `uvm_fatal` and produce read data for a WRAP burst. Compute each
  beat's address with the §1 wrap formula, read `mem` at those (word-aligned)
  addresses, and place the bytes on the right lanes. Mirror the existing INCR/FIXED
  branches in the same function.
- **`write_transaction_to_mem`** (grep `task write_transaction_to_mem`): today it
  dispatches to `write_incr_burst_transaction_to_mem` / `write_fixed_burst_...`.
  Add a `write_wrap_burst_transaction_to_mem` that writes each beat to its wrapped
  address. Without it, WRAP writes are silently dropped from the memory model and
  read-back checks will mismatch.

### 3.4 `src/ovip_axi_master_driver.sv` / `src/ovip_axi_slave_driver.sv`

- The drivers already drive `awburst`/`arburst <= tr.burst` and place data via
  `transfer_starting_byte_lane`, so they should "just work" once 3.1 is done.
- **Verify** there are no INCR-only assumptions in the data-driving loops
  (search the drivers for any beat→address/lane math that assumes monotonic
  increment). The address channel only carries the start address, so the driver
  doesn't compute the wrap itself — the DUT does — but the **data placement** must
  match the wrapped lanes.

### 3.5 `src/ovip_axi_agent_config.sv` — `check_config`

- WRAP is legal on AXI3 and AXI4 but **not** on AXI4-Lite (no bursts). Add a
  guard in `check_config` rejecting WRAP-capable configs on `OVIP_PROTOCOL_AXI4_LITE`
  if a knob exists, or document that WRAP requires a full-AXI agent.

### 3.6 Sequences & tests (verification of the above)

- Add a WRAP stimulus path: either extend `simple_rd/wr_bursts_seq` to allow
  `burst = OVIP_AXI_BURST_WRAP` with a constrained length ∈ {2,4,8,16} and a
  size-aligned address, or add a dedicated WRAP sequence.
- Add a directed test (and register it in `verif/ovip_axi_testbench/lib/regr.yaml`)
  that covers: all four lengths (2/4/8/16); the wrap point itself (start not at the
  window base, so it actually wraps); narrow transfers (`burst_size < bus_width`);
  and a write-then-read data-integrity check through the memory model.

---

## 4. Suggested implementation order

1. **`ovip_axi_trans`** (3.1): `calculate_transfer_starting_byte_lane`, then
   `check_strb`. Unit-think the wrap math with the §1 example first.
2. **Monitor** (3.2): un-fatal `check_address_phase`; confirm reconstruction.
3. **Slave responder** (3.3): `populate_data_from_mem` + `write_*_to_mem`
   (and decide the `reshape_axi_transaction` strategy from 3.1).
4. **Stimulus + test** (3.6) — bring this up early alongside step 1 so you can
   iterate against real waveforms.
5. **Config guard** (3.5) and **docs** (add a WRAP subsection to
   `verif/ovip_axi/README.md` "Basic Timings", drop the WRAP bullet from
   `CONTRIBUTING.md`, and update `CHANGELOG.md` "Known limitations").

---

## 5. Things to verify (test plan)

- [ ] All four WRAP lengths (2, 4, 8, 16) reconstruct correctly in the monitor.
- [ ] Wrap actually occurs: start address mid-window wraps to the window base.
- [ ] Narrow WRAP (`2^AxSIZE < bus_width`) places each beat on the correct lane.
- [ ] Write WRAP → read back (INCR or WRAP) through the memory model matches.
- [ ] Misaligned start address and illegal length (e.g. 3) are flagged as errors,
      not crashes.
- [ ] WRAP never crosses 4 KiB (sanity — should be impossible by construction).
- [ ] `monitor_error`/SLVERR path behaves for malformed WRAP (ties into the
      existing request-validity wiring).

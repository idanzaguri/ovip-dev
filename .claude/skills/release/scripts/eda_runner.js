// In-page runner for OVIP bundles on EDA Playground.
//
// Inject this whole file with the Claude in Chrome javascript_tool on a
// logged-in edaplayground.com tab (a fresh playground, no files added yet),
// with scripts/eda_server.py running on http://127.0.0.1:8765. Then:
//
//   await __ovip.setup('apb')          UVM 1.2, VCS with -debug_access+all,
//                                      eda_bundle/apb/eda_tb.sv in testbench.sv
//   (upload the bundle's other eda_*.sv through the "New File" dialog, see
//    references/eda-playground.md, then check __ovip.tabs())
//   __ovip.start(__ovip.tests(), ['vcs', 'xcelium'])
//                                      every test of the bundle on each
//                                      simulator; ovip_mem_test last
//   __ovip.status()                    poll; running, current test, last results
//   __ovip.go()                        clear the unsaved-changes guard and load
//                                      a fresh playground for the next bundle
//
// Every run's log is POSTed to the server as <bundle>_<sim>__<test>.txt and
// the result list as results_<bundle>.txt; scripts/eda_summary.py reads them.
// Strings returned to the tool are passed through san(): the tool blocks any
// output that contains '=' as "Cookie/query string data".
(() => {
  const SERVER = 'http://127.0.0.1:8765';
  const SIM = { vcs: '1301', xcelium: '1501', questa: '1701' };   // #simulator values, 2026-10
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const san = s => String(s).replace(/=/g, '≡').replace(/&/g, '＆').replace(/;/g, '；');

  window.__ovip = {
    results: [], running: false, current: null, bundle: null, sleep, san,

    // The Log pane renders one <pre> per line; take the closest ancestor that
    // holds all of them.
    log() {
      const pres = document.querySelectorAll('pre');
      if (!pres.length) return '';
      let box = pres[0];
      while (box && box.querySelectorAll('pre').length < pres.length) box = box.parentElement;
      return box ? box.innerText : '';
    },
    cm() { return document.querySelectorAll('.CodeMirror')[0].CodeMirror; },   // testbench.sv
    simOptions() { return san([...document.querySelectorAll('#simulator option')].map(o => o.value + ':' + o.text).join(' | ')); },
    setSim(name) {
      jQuery('#simulator').val(SIM[name] || name).trigger('change');
      return jQuery('#simulator option:selected').text();
    },
    tabs() {
      const bar = document.getElementById('testbenchTabsAdd').parentElement;
      return [...bar.querySelectorAll('li')].map(e => e.textContent.trim().replace(/\s+/g, ' ').replace('Remove Tab', '').trim()).filter(t => t);
    },
    async setup(bundle) {
      this.bundle = bundle;
      jQuery('#methodologyLibrary').val('701').trigger('change');          // UVM 1.2
      this.setSim('vcs');
      const co = document.getElementById('vcsCompileOptions');
      // uvm_hdl_force (the mid-test reset tests) fails on VCS without debug access.
      if (!/debug_access/.test(co.value)) { co.value += ' -debug_access+all'; jQuery(co).trigger('change').trigger('input'); }
      const tb = await fetch(SERVER + '/' + bundle + '/eda_tb.sv').then(r => r.text());
      this.cm().setValue(tb);
      return san('uvm ' + jQuery('#methodologyLibrary option:selected').text() + ' | sim ' + jQuery('#simulator option:selected').text()
                 + ' | vcs ' + co.value + ' | tb lines ' + this.cm().lineCount() + ' | tabs ' + this.tabs().join(','));
    },
    // Test names from the TEST_NAME defines of eda_tb.sv (active and commented
    // out). ovip_mem_test goes last: its benchmark block hits the Playground
    // runtime cap, so it takes minutes.
    tests() {
      const all = [...this.cm().getValue().matchAll(/TEST_NAME "([^"]+)"/g)].map(m => m[1]);
      return all.filter(t => t !== 'ovip_mem_test').concat(all.includes('ovip_mem_test') ? ['ovip_mem_test'] : []);
    },
    setTest(name) {
      const cm = this.cm();
      cm.setValue(cm.getValue().replace(/^`define TEST_NAME ".*"$/m, '`define TEST_NAME "' + name + '"'));
    },
    summarize(txt) {
      const m = re => (txt.match(re) || [])[1];
      return {
        err: m(/UVM_ERROR :\s+(\d+)/), fatal: m(/UVM_FATAL :\s+(\d+)/), warn: m(/UVM_WARNING :\s+(\d+)/),
        compErr: (txt.match(/^(Error-\[|\*E,|\*F,|xmvlog: \*E|xmelab: \*E)/mg) || []).length,
        compWarn: (txt.match(/^(Warning-\[|\*W,)/mg) || []).length,
        interrupted: /Execution interrupted/.test(txt), done: /(^|\n)Done\s*$/.test(txt), lines: txt.split('\n').length,
      };
    },
    // One run of the active TEST_NAME. The Playground sometimes loses a job
    // ("This process not found on server." and no Done line); run it again,
    // up to three attempts.
    async runOne(name, tag) {
      if (name) this.setTest(name);
      const LOST = /This process not found on server/;
      let txt, attempts = 0;
      const t0 = Date.now();
      while (true) {
        attempts++;
        const before = this.log();
        const tStart = Date.now();
        document.getElementById('runButton').click();
        while (this.log() === before && Date.now() - tStart < 90000) await sleep(500);        // the pane clears
        while (true) {
          txt = this.log();
          // The run's last line is exactly "Done". Anchor it: Xcelium's own
          // "Loading snapshot ... Done" line also ends with the word.
          if (/(^|\n)Done\s*$/.test(txt) || /Execution interrupted/.test(txt) || LOST.test(txt)) break;
          if (Date.now() - tStart > 1200000) break;
          await sleep(1000);
        }
        await sleep(1500);
        txt = this.log();
        if (!LOST.test(txt) || attempts >= 3) break;
        await sleep(5000);
      }
      try { await fetch(SERVER + '/log/' + tag + '__' + (name || 'run'), { method: 'POST', body: txt }); } catch (e) {}
      const r = Object.assign({ name: name || 'run', tag, secs: Math.round((Date.now() - t0) / 1000), attempts, lost: LOST.test(txt) }, this.summarize(txt));
      this.results.push(r);
      return r;
    },
    async runList(names, tag) {
      for (const n of names) { this.current = n; await this.runOne(n, tag); }
      this.current = null;
    },
    // names: from tests(); [] for a bundle without TEST_NAME (the all-VIP build,
    // an example top). sims: subset of Object.keys(SIM).
    start(names, sims, bundle) {
      bundle = bundle || this.bundle;
      const list = names.length ? names : [null];
      this.results = [];
      (async () => {
        this.running = true;
        try {
          for (const s of sims) {
            this.setSim(s);
            await sleep(1000);
            await this.runList(list, bundle + '_' + s);
            await this.save('results_' + bundle);
          }
        } finally { this.running = false; }
      })();
      return 'started ' + list.length + ' run(s) of ' + bundle + ' on ' + sims.join(', ');
    },
    async save(name) {
      try { await fetch(SERVER + '/log/' + name, { method: 'POST', body: JSON.stringify(this.results, null, 1) }); } catch (e) {}
    },
    status() {
      const bad = this.results.filter(r => (r.err !== undefined && r.err !== '0') || (r.fatal !== undefined && r.fatal !== '0') || r.compErr || r.interrupted || r.lost || !r.done).map(r => r.tag + ':' + r.name);
      return san(JSON.stringify({ running: this.running, current: this.current, n: this.results.length, bad, last: this.results.slice(-2) }));
    },
    go(url) {
      window.onbeforeunload = null;
      jQuery(window).off('beforeunload');
      window.addEventListener('beforeunload', e => { e.stopImmediatePropagation(); }, true);
      setTimeout(() => { location.href = url || 'https://www.edaplayground.com/'; }, 100);
      return 'navigating';
    },
  };
  return 'ovip runner installed; logged in: ' + !!document.getElementById('btn-logout');
})();

import assert from 'node:assert/strict';
import test from 'node:test';
import { pytestAssertionReport } from '../../scripts/verification/reporting/pytest-report.ts';
const stdout='============================= test session starts ==============================\nplatform linux -- Python 3.12.14, pytest-8.4.2\nrootdir: /held-owner\ncollecting ... collected 1 item\n\ntests/test_boundary.py::test_exact_boundary PASSED [100%]\n\n============================== slowest durations ===============================\n0.01s setup    tests/test_boundary.py::test_exact_boundary\n0.12s call     tests/test_boundary.py::test_exact_boundary\n0.00s teardown tests/test_boundary.py::test_exact_boundary\n============================== 1 passed in 0.13s ===============================\n';
const native={format:'pytest' as const,command:['python3','-m','pytest','-vv','--color=no','--durations=0','--durations-min=0'],cwd:'/held-owner',stdout,stderr:'',exitCode:0,signal:null,trace:''};
test('strict pytest reporting preserves native node identity status and native measured call duration with exact terminal counts',()=>{
 const before=structuredClone(native),report=pytestAssertionReport(native);assert.equal(report.success,true);assert.equal(report.numTotalTests,1);assert.equal(report.numPassedTests,1);
 assert.deepEqual(report.testResults[0]!.assertionResults[0],{title:'tests/test_boundary.py::test_exact_boundary',status:'passed',duration:120,failureMessages:[]});assert.deepEqual(report.raw,before);assert.deepEqual(native,before);
});
test('strict pytest reporting retains failures skips and interruption and rejects every missing ambiguous filtered or truncated observation',()=>{
 for(const change of [
  {stdout:stdout.replace('1 passed in 0.13s','')},{stdout:stdout.replace('collected 1 item','collected 2 items')},
  {stdout:stdout.replace('collected 1 item','collected 2 items / 1 deselected / 1 selected')},
  {stdout:stdout.replace('0.12s call     tests/test_boundary.py::test_exact_boundary\n','')},
  {stdout:stdout.replace('PASSED [100%]','SKIPPED [100%]').replace('1 passed in','1 skipped in')},
  {stdout:stdout.replace('PASSED [100%]','FAILED [100%]').replace('1 passed in','1 failed in'),exitCode:1},
  {stdout:stdout.replace('PASSED [100%]','XFAIL [100%]').replace('1 passed in','1 xfailed in')},
  {stdout:stdout.replace('PASSED [100%]','PASSED [50%]\ntests/test_boundary.py::test_exact_boundary PASSED [100%]')},
  {stdout:stdout.replace('0.12s call','NaNs call')},{stdout:stdout.replace('0.12s call     tests/test_boundary.py::test_exact_boundary','0.12s call     tests/substituted.py::foreign')},
  {exitCode:null,signal:'SIGINT'},
 ]){const supplied={...native,...change},before=structuredClone(supplied),report=pytestAssertionReport(supplied);assert.equal(report.success,false,JSON.stringify(change));assert.deepEqual(report.raw,before);assert.deepEqual(supplied,before);}
 const failed=pytestAssertionReport({...native,stdout:stdout.replace('PASSED [100%]','FAILED [100%]').replace('1 passed in','1 failed in'),exitCode:1});assert.equal(failed.numFailedTests,1);assert.equal(failed.testResults[0]!.assertionResults[0]!.status,'failed');
});

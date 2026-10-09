import assert from 'node:assert/strict';
import test from 'node:test';
import { exUnitAssertionReport } from '../../scripts/verification/reporting/exunit-report.ts';
const stdout='Running ExUnit with seed: 42, max_cases: 1\n\nNative.BoundaryTest [test/boundary_test.exs]\n  * test exact boundary [L#4]\u001b[32m\r  * test exact boundary (100.2ms) [L#4]\u001b[0m\n\nFinished in 0.1 seconds (0.00s async, 0.1s sync)\n\u001b[32m1 test, 0 failures\u001b[0m\n';
const native={format:'exunit' as const,command:['mix','test','--trace','--color'],cwd:'/held-owner',stdout,stderr:'',exitCode:0,signal:null,trace:''};
test('strict ExUnit reporting retains native module file test status and measured duration with exact summary reconciliation',()=>{
 const before=structuredClone(native),report=exUnitAssertionReport(native);
 assert.equal(report.success,true);assert.equal(report.numTotalTests,1);assert.equal(report.numPassedTests,1);
 assert.equal(report.testResults[0]!.name,'Native.BoundaryTest [test/boundary_test.exs]');
 assert.deepEqual(report.testResults[0]!.assertionResults[0],{title:'test exact boundary [L#4]',status:'passed',duration:100.2,failureMessages:[]});
 assert.deepEqual(report.raw,before);assert.deepEqual(native,before);
});
test('strict ExUnit reporting preserves native failures and skipped dispositions while rejecting incomplete unknown or filtered evidence',()=>{
 const failed=exUnitAssertionReport({...native,stdout:stdout.replace('\u001b[32m\r','\u001b[31m\r').replace('0 failures','1 failure'),exitCode:2});
 assert.equal(failed.success,false);assert.equal(failed.numFailedTests,1);assert.equal(failed.testResults[0]!.assertionResults[0]!.status,'failed');
 const skipped=exUnitAssertionReport({...native,stdout:stdout.replace('\u001b[32m\r','\u001b[33m\r').replace('100.2ms','skipped').replace('0 failures','0 failures, 1 skipped')});
 assert.equal(skipped.success,false);assert.equal(skipped.numPendingTests,1);
 for(const change of [
  {stdout:stdout.replace('1 test, 0 failures','')},{stdout:stdout.replace('Finished in 0.1 seconds (0.00s async, 0.1s sync)','')},
  {stdout:stdout.replace('1 test, 0 failures','2 tests, 0 failures')},{stdout:stdout.replace('0 failures','0 failures, 1 excluded')},
  {stdout:stdout.replace('100.2ms','NaNms')},{stdout:stdout.replace('\u001b[32m\r','\u001b[35m\r')},
  {stdout:stdout.replace('Native.BoundaryTest [test/boundary_test.exs]\n','')},
  {stdout:stdout.replace('\u001b[0m\n\nFinished','\u001b[0m\n'+stdout.split('\n')[3]+'\nFinished')},
  {exitCode:null,signal:'SIGTERM'},
 ]){const supplied={...native,...change},before=structuredClone(supplied),report=exUnitAssertionReport(supplied);assert.equal(report.success,false,JSON.stringify(change));assert.deepEqual(report.raw,before);assert.deepEqual(supplied,before);}
});

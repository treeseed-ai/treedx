import assert from 'node:assert/strict';
import test from 'node:test';
import { nativeAssertionReport } from '../../scripts/verification/reporting/native-report.ts';

const output = 'running 1 test\ntest boundary ... ok\n\ntest result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.50s\n';
const trace = [
 '104 1770000000.000000 write(1, "running 1 test\\n", 15) = 15',
 '104 1770000000.100000 write(1, "test boundary ... ", 18) = 18',
 '104 1770000000.600000 write(1, "ok\\n", 3) = 3',
 '104 1770000000.601000 write(1, "\\ntest result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.50s\\n", 103) = 103',
].join('\n');
const observation = { format: 'rust' as const, command: ['cargo','test','--workspace','--','--test-threads=1','--color','never'],
 cwd: '/held-owner', stdout: output, stderr: '     Running unittests src/lib.rs (/tmp/target/debug/deps/native-abc)\n', exitCode: 0, signal: null, trace };

test('strict native reporting retains every Rust identity and measured syscall interval with exact terminal counts',()=>{
 const before=structuredClone(observation), report=nativeAssertionReport(observation);
 assert.equal(report.success,true);assert.equal(report.numTotalTests,1);assert.equal(report.numPassedTests,1);
 assert.equal(report.numFailedTests,0);assert.equal(report.numPendingTests,0);assert.equal(report.numTodoTests,0);
 assert.equal(report.testResults.length,1);assert.equal(report.testResults[0]!.assertionResults[0]!.title,'boundary');
 assert.equal(report.testResults[0]!.assertionResults[0]!.duration,500);
 assert.deepEqual(report.raw,observation);assert.deepEqual(observation,before);
});
test('strict native reporting never invents Rust test durations from exit zero or a terminal summary',()=>{
 const report=nativeAssertionReport({...observation,trace:''});
 assert.equal(report.success,false);assert.ok(report.errors.includes('test_timing_unavailable'));
 assert.equal(report.testResults[0]!.assertionResults[0]!.duration,null);
 assert.equal(report.testResults[0]!.assertionResults[0]!.status,'passed');
});
test('strict native reporting rejects truncated filtered ignored duplicate interrupted or conflicting native observations without repairing them',()=>{
 for(const change of [
  {stdout:'running 1 test\ntest boundary ... ok\n'},
  {stdout:output.replace('0 filtered out','1 filtered out')},
  {stdout:output.replace('0 ignored','1 ignored')},
  {stdout:output.replace('test boundary ... ok','test boundary ... ok\ntest boundary ... ok')},
  {signal:'SIGTERM',exitCode:null},
  {stdout:output.replace('1 passed','2 passed')},
  {trace:trace.replace('1770000000.600000','1770000000.050000')},
  {trace:trace.replace('test boundary ... ','test substituted ... ')},
 ]){
  const supplied={...observation,...change},before=structuredClone(supplied),report=nativeAssertionReport(supplied);
  assert.equal(report.success,false,JSON.stringify(change));assert.ok(report.errors.length>0);assert.deepEqual(report.raw,before);assert.deepEqual(supplied,before);
 }
});

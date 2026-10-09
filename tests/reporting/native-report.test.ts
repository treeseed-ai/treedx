import assert from 'node:assert/strict';
import test from 'node:test';
import { nativeAssertionReport } from '../../scripts/verification/reporting/native-report.ts';

const output = 'running 1 test\ntest boundary ... ok\n\ntest result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.50s\n';
const trace = [
 ['1770000000.000000','running 1 test\n'], ['1770000000.100000','test boundary ... '], ['1770000000.600000','ok\n'],
 ['1770000000.601000','\ntest result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.50s\n'],
].map(([time,bytes])=>`104 ${time} write(1, ${JSON.stringify(bytes)}, ${Buffer.byteLength(bytes!)}) = ${Buffer.byteLength(bytes!)}`).join('\n');
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
test('strict native reporting reconciles paired concurrent syscall records and rejects every incomplete or conflicting pair',()=>{
 const split=trace.replace('write(1, "ok\\n", 3) = 3','write(1, "ok\\n", 3 <unfinished ...>\n205 1770000000.600001 write(1, "cargo:build-script\\n", 19) = 19\n104 1770000000.600002 <... write resumed>) = 3');
 assert.notEqual(split,trace);
 const supplied={...observation,trace:split},before=structuredClone(supplied),report=nativeAssertionReport(supplied);
 assert.equal(report.success,true,JSON.stringify(report.errors));assert.equal(report.testResults[0]!.assertionResults[0]!.duration,500);
 assert.deepEqual(report.raw,before);assert.deepEqual(supplied,before);
 for(const changed of [
  split.replace('104 1770000000.600002 <... write resumed>) = 3',''),
  split.replace('104 1770000000.600002 <... write resumed>) = 3','999 1770000000.600002 <... write resumed>) = 3'),
  split.replace('<... write resumed>) = 3','<... write resumed>) = 2'),
  split.replace('1770000000.600002','1770000000.599999'),
  split.replace('104 1770000000.600000 write(1, "ok\\n", 3 <unfinished ...>',''),
  split.replace('104 1770000000.600002 <... write resumed>) = 3','104 1770000000.600002 <... write resumed>) = 3\n104 1770000000.600003 <... write resumed>) = 3'),
  split.replace('205 1770000000.600001','104 1770000000.600001'),
 ]){const failed={...observation,trace:changed},retained=structuredClone(failed),result=nativeAssertionReport(failed);assert.equal(result.success,false);assert.ok(result.errors.includes('native_trace_write_incomplete')||result.errors.includes('native_trace_clock_reversed'));assert.deepEqual(result.raw,retained);assert.deepEqual(failed,retained);}
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
  {trace:trace.split('\n').slice(0,-1).join('\n')},
 ]){
  const supplied={...observation,...change},before=structuredClone(supplied),report=nativeAssertionReport(supplied);
  assert.equal(report.success,false,JSON.stringify(change));assert.ok(report.errors.length>0);assert.deepEqual(report.raw,before);assert.deepEqual(supplied,before);
 }
});

import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { collectNativeCommand } from '../../scripts/verification/reporting/native-command.ts';
import { nativeAssertionReport } from '../../scripts/verification/reporting/native-report.ts';

test('native pytest execution retains actual node identities statuses call timings skips failure and interruption',async()=>{
 const root=mkdtempSync(join(tmpdir(),'treedx-pytest-report-'));
 try{
  const file=join(root,'test_boundary.py'),command=['python3','-m','pytest','-vv','--color=no','--durations=0','--durations-min=0'];
  const run=()=>collectNativeCommand(command,root,{format:'pytest'});
  writeFileSync(file,'import time\ndef test_exact_boundary():\n    time.sleep(0.12)\n    assert 2+2==4\n');
  const native=await run(),report=nativeAssertionReport(native);console.error(JSON.stringify({native,report}));
  assert.equal(report.success,true,JSON.stringify(report));assert.equal(report.numTotalTests,1);
  const assertion=report.testResults[0]!.assertionResults[0]!;assert.equal(assertion.title,'test_boundary.py::test_exact_boundary');assert.equal(assertion.status,'passed');assert.ok(assertion.duration!==null&&assertion.duration>=100);
  writeFileSync(file,'def test_exact_boundary():\n    assert 2+2==5\n');
  const failed=await run(),failedReport=nativeAssertionReport(failed);assert.equal(failedReport.success,false);assert.equal(failedReport.numFailedTests,1);assert.deepEqual(failedReport.raw,failed);
  writeFileSync(file,'import pytest\n@pytest.mark.skip(reason="native skip fixture")\ndef test_exact_boundary():\n    assert 2+2==4\n');
  const skipped=await run(),skippedReport=nativeAssertionReport(skipped);assert.equal(skippedReport.success,false);assert.equal(skippedReport.numPendingTests,1);assert.deepEqual(skippedReport.raw,skipped);
  writeFileSync(file,'import time\ndef test_exact_boundary():\n    time.sleep(60)\n');
  const controller=new AbortController();const interrupted=await collectNativeCommand(command,root,{format:'pytest',signal:controller.signal,onStdout:chunk=>{if(chunk.includes('test_boundary.py::test_exact_boundary'))controller.abort();}});
  const interruptedReport=nativeAssertionReport(interrupted);assert.equal(interruptedReport.success,false);assert.ok(interruptedReport.errors.includes('native_process_failed_or_interrupted'));assert.deepEqual(interruptedReport.raw,interrupted);
 }finally{rmSync(root,{recursive:true,force:true});}
});

import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { collectNativeCommand } from '../../scripts/verification/reporting/native-command.ts';
import { nativeAssertionReport } from '../../scripts/verification/reporting/native-report.ts';
test('native Node event collection retains actual assertions timing failure skip todo and process interruption',async()=>{
 const root=mkdtempSync(join(tmpdir(),'treedx-node-report-'));
 try{
  const file=join(root,'boundary.test.ts'),command=[process.execPath,'--test',file],run=()=>collectNativeCommand(command,root,{format:'node'});
  writeFileSync(file,"import test from 'node:test';import assert from 'node:assert/strict';test('exact boundary',()=>assert.equal(2+2,4));\n");
  const native=await run(),report=nativeAssertionReport(native);assert.equal(report.success,true,JSON.stringify(report));assert.equal(report.numTotalTests,1);assert.equal(report.testResults[0]!.assertionResults[0]!.title,'exact boundary');assert.deepEqual(report.raw,native);
  writeFileSync(file,"import test from 'node:test';test('exact boundary',()=>{throw new Error('original failure');});\n");
  const failed=await run(),failedReport=nativeAssertionReport(failed);assert.equal(failedReport.success,false);assert.equal(failedReport.numFailedTests,1);assert.deepEqual(failedReport.raw,failed);
  for(const status of ['skip','todo']){writeFileSync(file,`import test from 'node:test';test.${status}('exact boundary',()=>{});\n`);const pending=await run(),pendingReport=nativeAssertionReport(pending);assert.equal(pendingReport.success,false);assert.equal(status==='skip'?pendingReport.numPendingTests:pendingReport.numTodoTests,1);assert.deepEqual(pendingReport.raw,pending);}
  writeFileSync(file,"import test from 'node:test';test('exact boundary',async()=>{console.log('native-ready');await new Promise(resolve=>setTimeout(resolve,60000));});\n");
  const controller=new AbortController(),interrupted=await collectNativeCommand(command,root,{format:'node',signal:controller.signal,onStdout:chunk=>{if(chunk.includes('native-ready'))controller.abort();}});
  const interruptedReport=nativeAssertionReport(interrupted);assert.equal(interruptedReport.success,false);assert.ok(interruptedReport.errors.includes('native_process_failed_or_interrupted'));assert.deepEqual(interruptedReport.raw,interrupted);
 }finally{rmSync(root,{recursive:true,force:true});}
});

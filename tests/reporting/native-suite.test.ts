import assert from 'node:assert/strict';
import test from 'node:test';
import { execFile } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { promisify } from 'node:util';
import { collectNativeSuite, combineNativeReports } from '../../scripts/verification/reporting/native-suite.ts';
import { nativeAssertionReport } from '../../scripts/verification/reporting/native-report.ts';
const native={format:'node' as const,command:['node','--test','unit.test.ts'],cwd:'/held-owner',stdout:[{type:'test:pass',data:{name:'exact boundary',file:'/held-owner/unit.test.ts',details:{type:'test',duration_ms:1.23}}},{type:'test:summary',data:{success:true,counts:{tests:1,passed:1,failed:0,cancelled:0,skipped:0,todo:0}}}].map(value=>JSON.stringify(value)).join('\n')+'\n',stderr:'',exitCode:0,signal:null,trace:''};
const run={command:['bash','test-all.sh'],cwd:'/held-owner',stdout:'original owning output\n',stderr:'',exitCode:0,signal:null};
test('complete native suite collection retains exact native counts commands observations and test identities without mutation',()=>{
 const reports=[nativeAssertionReport(native),nativeAssertionReport({...native,command:['node','--test','integration.test.ts']})],before=structuredClone(reports),result=combineNativeReports(reports,run);
 assert.equal(result.success,true);assert.equal(result.numTotalTests,2);assert.equal(result.numPassedTests,2);assert.equal(result.testResults.length,2);assert.deepEqual(result.nativeReports,before);assert.deepEqual(result.execution,run);assert.deepEqual(reports,before);
});
test('complete native suite collection never certifies missing or partial reports interrupted scripts or malformed assertion totals',()=>{
 const complete=nativeAssertionReport(native);
 for(const reports of [[],[{...complete,numTotalTests:2}],[{...complete,testResults:[]}],[{...complete,success:false}],[{...complete,numPendingTests:1}]] )assert.equal(combineNativeReports(reports,run).success,false);
 for(const execution of [{...run,exitCode:1},{...run,signal:'SIGTERM',exitCode:null}]){const result=combineNativeReports([complete],execution);assert.equal(result.success,false);assert.deepEqual(result.execution,execution);}
});

test('original shell entrypoint and public reporting command retain native assertions failed history and interrupted cleanup',async()=>{
 const root=mkdtempSync(join(tmpdir(),'treedx native suite ')),helper=resolve(import.meta.dirname,'../../scripts/verification/reporting/command.ts');
 const quote=(value:string)=>`'${value.replaceAll("'","'\\''")}'`;
 try{
  const file=join(root,'boundary.test.ts'),script=join(root,'whole.sh'),cleanup=join(root,'cleanup'),pid=join(root,'native.pid');
  const shell=`#!/usr/bin/env bash\nset -euo pipefail\ntrap ${quote(`printf closed > ${quote(cleanup)}`)} EXIT\ntrap 'exit 143' TERM\n${quote(process.execPath)} ${quote(helper)} node -- ${quote(process.execPath)} --test ${quote(file)}\n`;
  writeFileSync(script,shell);writeFileSync(file,"import test from 'node:test';import assert from 'node:assert/strict';test('exact public boundary',()=>assert.equal(2+2,4));\n");
  const publicRun=await promisify(execFile)(process.execPath,[helper,'suite','--','bash',script],{cwd:root,encoding:'utf8'});
  const complete=JSON.parse(publicRun.stdout);assert.equal(complete.success,true);assert.equal(complete.numTotalTests,1);assert.equal(complete.numPassedTests,1);
  assert.equal(complete.nativeReports[0].testResults[0].assertionResults[0].title,'exact public boundary');
  assert.deepEqual(complete.execution.command,['bash',script]);assert.match(complete.execution.stdout,/exact public boundary/u);assert.equal(readFileSync(cleanup,'utf8'),'closed');
  writeFileSync(file,"import test from 'node:test';test('exact public boundary',()=>{throw new Error('original failed boundary');});\n");
  const failed=await collectNativeSuite(['bash',script],root);assert.equal(failed.success,false);assert.equal(failed.numFailedTests,1);assert.match(failed.execution.stdout,/original failed boundary/u);
  const retained=structuredClone(failed);
  writeFileSync(file,"import test from 'node:test';test.skip('exact public boundary',()=>{});\n");
  const skipped=await collectNativeSuite(['bash',script],root);assert.equal(skipped.success,false);assert.equal(skipped.numPendingTests,1);
  for(const output of ["printf '{bad-json}\\n' >&3\n","printf '{\\\"raw\\\":{}}' >&3\n",'true\n']){
   writeFileSync(script,output);const invalid=await collectNativeSuite(['bash',script],root);assert.equal(invalid.success,false);assert.equal(invalid.execution.exitCode,0);
  }
  writeFileSync(script,shell);rmSync(cleanup);writeFileSync(file,`import test from 'node:test';import {writeFileSync} from 'node:fs';test('exact public boundary',async()=>{writeFileSync(${JSON.stringify(pid)},String(process.pid));console.log('native-ready');await new Promise(resolve=>setTimeout(resolve,60000));});\n`);
  const controller=new AbortController(),interrupted=await collectNativeSuite(['bash',script],root,{signal:controller.signal,onStdout:chunk=>{if(chunk.includes('native-ready'))controller.abort();}});
  assert.equal(interrupted.success,false);assert.ok(interrupted.errors.includes('native_owner_process_failed_or_interrupted'));assert.equal(readFileSync(cleanup,'utf8'),'closed');
  assert.throws(()=>process.kill(Number(readFileSync(pid,'utf8')),0),{code:'ESRCH'});
  assert.deepEqual(failed,retained);
 }finally{rmSync(root,{recursive:true,force:true});}
});

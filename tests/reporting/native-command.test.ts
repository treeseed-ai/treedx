import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { collectNativeCommand } from '../../scripts/verification/reporting/native-command.ts';
import { nativeAssertionReport } from '../../scripts/verification/reporting/native-report.ts';

test('native Cargo execution retains real assertion identities timing counts and raw failed ignored and interrupted observations', async()=>{
 const root=mkdtempSync(join(tmpdir(),'treedx-native-report-'));
 try{
  const toolchain=execFileSync('rustc',['--version'],{encoding:'utf8'}).trim();
  assert.match(toolchain,/^rustc 1\.99\.0 /u);
  writeFileSync(join(root,'Cargo.toml'),'[package]\nname="strict_report_fixture"\nversion="0.1.0"\nedition="2021"\n');
  mkdirSync(join(root,'src'));
  const lib=join(root,'src/lib.rs');
  const run=()=>collectNativeCommand(['cargo','test','--offline','--','--test-threads=1','--color','never'],root);
  writeFileSync(lib,'#[test] fn exact_boundary() { std::thread::sleep(std::time::Duration::from_millis(100)); assert_eq!(2+2,4); }\n');
  const native=await run(),report=nativeAssertionReport(native);
  console.error(JSON.stringify({toolchain,native,report}));
  assert.equal(report.success,true,JSON.stringify(report));assert.equal(report.numTotalTests,1);
  const assertion=report.testResults.flatMap(suite=>suite.assertionResults)[0]!;
  assert.equal(assertion.title,'exact_boundary');assert.equal(assertion.status,'passed');
  assert.ok(assertion.duration!==null&&assertion.duration>=100);assert.deepEqual(report.raw,native);
  writeFileSync(lib,'#[test] fn exact_boundary() { assert_eq!(2+2,5); }\n');
  const failed=await run(),failedReport=nativeAssertionReport(failed);
  assert.equal(failedReport.success,false);assert.equal(failedReport.numFailedTests,1);assert.deepEqual(failedReport.raw,failed);
  writeFileSync(lib,'#[test] #[ignore] fn exact_boundary() {}\n');
  const ignored=await run(),ignoredReport=nativeAssertionReport(ignored);
  assert.equal(ignoredReport.success,false);assert.equal(ignoredReport.numPendingTests,1);assert.deepEqual(ignoredReport.raw,ignored);
  writeFileSync(lib,'#[test] fn exact_boundary() { std::thread::sleep(std::time::Duration::from_secs(60)); }\n');
  const controller=new AbortController();
  const interrupted=await collectNativeCommand(['cargo','test','--offline','--','--test-threads=1','--color','never'],root,{
   signal:controller.signal,onStdout:chunk=>{if(chunk.includes('test exact_boundary ... '))controller.abort();},
  });
  const interruptedReport=nativeAssertionReport(interrupted);
  assert.equal(interruptedReport.success,false);assert.ok(interruptedReport.errors.includes('native_process_failed_or_interrupted'));
  assert.deepEqual(interruptedReport.raw,interrupted);
 }finally{rmSync(root,{recursive:true,force:true});}
});

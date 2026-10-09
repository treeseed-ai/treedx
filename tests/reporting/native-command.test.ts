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
  const run=()=>collectNativeCommand(['cargo','test','--offline','--','--test-threads=1','--color','never'],root,{format:'rust'});
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
   format:'rust',signal:controller.signal,onStdout:chunk=>{if(chunk.includes('test exact_boundary ... '))controller.abort();},
  });
  const interruptedReport=nativeAssertionReport(interrupted);
  assert.equal(interruptedReport.success,false);assert.ok(interruptedReport.errors.includes('native_process_failed_or_interrupted'));
  assert.deepEqual(interruptedReport.raw,interrupted);
 }finally{rmSync(root,{recursive:true,force:true});}
});

test('native ExUnit execution retains actual colored statuses timings doctests failures skips and terminal completion',async()=>{
 const root=mkdtempSync(join(tmpdir(),'treedx-exunit-report-'));
 try{
  writeFileSync(join(root,'mix.exs'),'defmodule ReportFixture.MixProject do\n use Mix.Project\n def project, do: [app: :report_fixture, version: "0.1.0"]\nend\n');
  mkdirSync(join(root,'test'));writeFileSync(join(root,'test/test_helper.exs'),'ExUnit.start()\n');
  mkdirSync(join(root,'lib'));writeFileSync(join(root,'lib/report_fixture.ex'),'defmodule ReportFixture do\n @doc \"\"\"\n Returns a measured example.\n\n     iex> ReportFixture.example()\n     4\n \"\"\"\n def example, do: 4\nend\n');
  const file=join(root,'test/boundary_test.exs'),run=()=>collectNativeCommand(['mix','test','--trace','--color'],root,{format:'exunit'});
  writeFileSync(file,'defmodule BoundaryTest do\n use ExUnit.Case\n doctest ReportFixture\n test "exact boundary" do\n Process.sleep(100)\n assert 2+2==4\n end\nend\n');
  const native=await run(),report=nativeAssertionReport(native);console.error(JSON.stringify({native,report}));
  assert.equal(report.success,true,JSON.stringify(report));assert.equal(report.numTotalTests,2);
  const assertion=report.testResults.flatMap(suite=>suite.assertionResults).find(value=>value.title==='test exact boundary [L#4]')!;
  assert.equal(assertion.title,'test exact boundary [L#4]');assert.equal(assertion.status,'passed');assert.ok(assertion.duration!==null&&assertion.duration>=100);
  writeFileSync(file,'defmodule BoundaryTest do\n use ExUnit.Case\n test "exact boundary", do: assert(2+2==5)\nend\n');
  const failed=await run(),failedReport=nativeAssertionReport(failed);assert.equal(failedReport.success,false);assert.equal(failedReport.numFailedTests,1);assert.deepEqual(failedReport.raw,failed);
  writeFileSync(file,'defmodule BoundaryTest do\n use ExUnit.Case\n @tag :skip\n test "exact boundary", do: assert(2+2==4)\nend\n');
  const skipped=await run(),skippedReport=nativeAssertionReport(skipped);assert.equal(skippedReport.success,false);assert.equal(skippedReport.numPendingTests,1);assert.deepEqual(skippedReport.raw,skipped);
 }finally{rmSync(root,{recursive:true,force:true});}
});

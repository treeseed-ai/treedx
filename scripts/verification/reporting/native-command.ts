import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { NativeObservation } from './native-report.ts';

/** Observe the original native command without replacing its owning test harness. */
export async function collectNativeCommand(command:string[],cwd:string, options:{format:NativeObservation['format'];signal?:AbortSignal;onStdout?:(chunk:string)=>void;onStderr?:(chunk:string)=>void}):Promise<NativeObservation>{
 if(!command.length||command.some(value=>!value||value.includes('\0')))throw new Error('Native command identity is required.');
 const root=await mkdtemp(join(tmpdir(),'treedx-native-trace-')),path=join(root,'writes.log');
 try{
  const reportPath=join(root,'report.json');
  const nativeCommand=options.format==='vitest'?[...command,'--', '--reporter=json',`--outputFile=${reportPath}`]:options.format==='node'?[command[0]!,`--test-reporter=${fileURLToPath(new URL('./node-events.ts',import.meta.url))}`,...command.slice(1)]:[...command];
  const executable=options.format==='rust'?'/usr/bin/strace':nativeCommand[0]!;
  const args=options.format==='rust'?['-f','-ttt','-xx','-s','16777216','-e','trace=write','-o',path,'--',...nativeCommand]:nativeCommand.slice(1);
  const env:NodeJS.ProcessEnv={...process.env,CARGO_TERM_COLOR:'never'};delete env.NODE_TEST_CONTEXT;
  const child=spawn(executable,args,{
   cwd,detached:true,stdio:['ignore','pipe','pipe'],env,
  });
  const stdout:Buffer[]=[],stderr:Buffer[]=[];
  const stop=()=>{if(child.pid){try{process.kill(-child.pid,'SIGTERM');}catch(error){if((error as NodeJS.ErrnoException).code!=='ESRCH')throw error;}}};
  const result=await new Promise<{exitCode:number|null;signal:NodeJS.Signals|null}>((resolve,reject)=>{
   child.stdout.on('data',(chunk:Buffer)=>{stdout.push(chunk);options.onStdout?.(chunk.toString('utf8'));});
   child.stderr.on('data',(chunk:Buffer)=>{stderr.push(chunk);options.onStderr?.(chunk.toString('utf8'));});
   child.once('error',reject);child.once('close',(exitCode,signal)=>resolve({exitCode,signal}));
   options.signal?.addEventListener('abort',stop,{once:true});if(options.signal?.aborted)stop();
  }).finally(()=>options.signal?.removeEventListener('abort',stop));
  const trace=options.format==='rust'?await readFile(path,'utf8'):'';
  return {format:options.format,command:nativeCommand,cwd,stdout:Buffer.concat(stdout).toString('utf8'),stderr:Buffer.concat(stderr).toString('utf8'),...result,trace,...(options.format==='vitest'?{report:await readFile(reportPath,'utf8').catch(()=>undefined)}:{})};
 }finally{await rm(root,{recursive:true,force:true});}
}

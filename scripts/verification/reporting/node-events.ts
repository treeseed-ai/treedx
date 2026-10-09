/** Serialize native TestsStream events without selecting tests or deriving results. */
export default async function* events(source:AsyncIterable<unknown>){
 for await(const event of source)yield JSON.stringify(event,(_key,value:unknown)=>value instanceof Error
  ? Object.fromEntries(Object.getOwnPropertyNames(value).map(key=>[key,(value as unknown as Record<string,unknown>)[key]])):value)+'\n';
}

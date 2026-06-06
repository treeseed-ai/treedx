import { RegistryAdapter } from '../adapters/index.js';
import type { TreeDxClientConfig, Transport } from '../types/index.js';
import { FetchTransport } from './transport.js';

export class TreeDxRegistryClient {
  readonly transport: Transport;
  readonly registry: RegistryAdapter;

  constructor(config: TreeDxClientConfig) {
    this.transport = config.transport ?? new FetchTransport(config);
    this.registry = new RegistryAdapter({ transport: this.transport });
  }
}

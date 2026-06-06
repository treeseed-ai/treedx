import { FederationAdapter } from '../adapters/index.js';
import type { TreeDxClientConfig, Transport } from '../types/index.js';
import { FetchTransport } from './transport.js';

export class TreeDxFederatedClient {
  readonly transport: Transport;
  readonly federation: FederationAdapter;

  constructor(config: TreeDxClientConfig) {
    this.transport = config.transport ?? new FetchTransport(config);
    this.federation = new FederationAdapter({ transport: this.transport });
  }
}

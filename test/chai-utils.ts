import chaiModule, {Assertion} from 'chai';
import {waffleChai} from '@ethereum-waffle/chai';

chaiModule.use(waffleChai);

export = chaiModule;

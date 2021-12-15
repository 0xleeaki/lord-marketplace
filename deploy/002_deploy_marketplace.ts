import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async ({deployments, getNamedAccounts}) => {
  const {deploy, execute, get} = deployments;
  const {creator} = await getNamedAccounts();
  console.log('> creator', creator);
  console.log('> Deploy Marketplace');

  const DOLA = await get('DOLA');

  await deploy('Marketplace', {
    contract: 'Marketplace',
    from: creator,
    log: true,
    args: [],
  });

  await execute('Marketplace', {from: creator, log: true}, 'initialize', DOLA.address);
};

export default func;

func.skip = async ({network}) => {
  return network.name != 'matic';
};

func.tags = ['Marketplace'];

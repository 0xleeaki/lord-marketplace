import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async ({deployments, getNamedAccounts, wellknown}) => {
  const {deploy, execute} = deployments;
  const {creator} = await getNamedAccounts();
  console.log('> creator', creator);
  console.log('> Deploy LordSkin NFT');

  await deploy('LordSkin', {
    contract: 'LordSkin',
    from: creator,
    log: true,
    args: [],
  });

  for (let i = 0; i < 5; i++) {
    await execute('LordSkin', {from: creator, log: true}, 'claim', i);
  }
};

export default func;

func.skip = async ({network}) => {
  return network.name != 'matic_done';
};

func.tags = ['LordSkin'];

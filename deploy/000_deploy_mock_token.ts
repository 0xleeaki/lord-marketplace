import {parseUnits} from 'ethers/lib/utils';
import {DeployFunction} from 'hardhat-deploy/types';
import {HardhatRuntimeEnvironment} from 'hardhat/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy, execute} = deployments;
  const {creator} = await getNamedAccounts();

  console.log('Deploy mock token with creator:', creator);

  await deploy('DOLA', {
    contract: 'MockERC20',
    from: creator,
    log: true,
    args: ['Mock DOLA Token', 'DOLA', 18],
  });

  await execute('DOLA', {from: creator, log: true}, 'mint', creator, parseUnits('1000000', 18));
};

export default func;

func.skip = async (hre) => {
  return hre.network.name != 'matic_done';
};

func.tags = ['MockToken'];

import {parseUnits, formatUnits} from 'ethers/lib/utils';
import {ethers} from 'hardhat';

const getDolaBalance = async (address: string) => {
  const dola = await ethers.getContract('DOLA');
  const balance = await dola.balanceOf(address);
  console.log('Creator balance', formatUnits(balance, 18));
};

async function main() {
  const [creator] = await ethers.getSigners();
  console.log('Creator', creator.address);

  const dola = await ethers.getContract('DOLA');
  console.log('DOLA token address', dola.address);

  await getDolaBalance(creator.address);

  console.log('Min...');
  await dola.connect(creator).mint(creator.address, parseUnits('100', 18));
}

main()
  .then(() => {
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
  })
  .then(() => {
    process.exit(1);
  });

import {Contract} from 'ethers';
import {deployments, getNamedAccounts, ethers} from 'hardhat';
import {expect} from './chai-utils';
import {parseUnits, toUtf8Bytes} from 'ethers/lib/utils';
import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signers';

const {deploy} = deployments;

const delay = (sec: number) => new Promise((resolve) => setTimeout(resolve, sec * 1000));

describe('Marketplace', async () => {
  let usdc: Contract;
  let skin: Contract;
  let market: Contract;
  let bider: SignerWithAddress;
  let seller: SignerWithAddress;

  const MaxUint256 = ethers.constants.MaxUint256;
  const mintAmount = parseUnits('10000', 18);
  const bidPrice = parseUnits('1000', 18);
  const fee = parseUnits('0.1', 6);

  before('Should deploy contract', async () => {
    const {creator} = await getNamedAccounts();
    bider = await ethers.getNamedSigner('creator');
    seller = await ethers.getNamedSigner('deployer');

    await deploy('USDC', {
      contract: 'MockERC20',
      from: creator,
      log: true,
      args: ['Mock USDC Token', 'USDC', 18],
    });

    usdc = await ethers.getContract('USDC');

    await deploy('LordSkin', {
      contract: 'LordSkin',
      from: creator,
      log: true,
      args: [],
    });

    skin = await ethers.getContract('LordSkin');

    await deploy('Marketplace', {
      contract: 'Marketplace',
      from: creator,
      log: true,
      args: [],
    });

    market = await ethers.getContract('Marketplace');

    await market.initialize(usdc.address);
  });

  before('Mock USDC: Mint token', async () => {
    await usdc.connect(bider).mint(bider.address, mintAmount);
    await usdc.connect(seller).mint(seller.address, mintAmount);
    await skin.connect(bider).setApprovalForAll(market.address, true);
    await skin.connect(seller).setApprovalForAll(market.address, true);
  });

  it('NFTSkin: Should return asset data', async () => {
    Array.from({length: 5}).forEach(async (_, id) => {
      await expect(skin.tokenURI(id)).to.not.reverted;
    });
  });

  it('NFTSkin: Should claim', async () => {
    await skin.connect(bider).claim(1);
    await skin.connect(bider).claim(2);
    await skin.connect(bider).claim(3);
    await skin.connect(bider).claim(4);
    await skin.connect(bider).claim(5);
    await skin.connect(bider).claim(6);
    await skin.connect(bider).claim(7);
    await skin.connect(bider).claim(8);
    await skin.connect(bider).claim(9);
    await skin.connect(bider).claim(10);
  });

  it('NFTSkin: Should transfer', async () => {
    await expect(skin.connect(bider).transferFrom(bider.address, seller.address, 6)).to.not.reverted;
    await expect(skin.connect(bider).transferFrom(bider.address, seller.address, 7)).to.not.reverted;
    await expect(skin.connect(bider).transferFrom(bider.address, seller.address, 8)).to.not.reverted;
    await expect(skin.connect(bider).transferFrom(bider.address, seller.address, 9)).to.not.reverted;
    await expect(skin.connect(bider).transferFrom(bider.address, seller.address, 10)).to.not.reverted;
  });

  it('Market: Should listing for sell', async () => {
    await expect(market.connect(seller).listingForSell(skin.address, 6, bidPrice)).to.not.reverted;
  });

  it('Market: Should cancel listing for sell', async () => {
    await expect(market.connect(seller).cancelListing(skin.address, 6)).to.not.reverted;
  });

  it('Market: Should listing for sell', async () => {
    await expect(market.connect(seller).listingForSell(skin.address, 6, bidPrice)).to.not.reverted;
  });

  it('Market: Should purchase', async () => {
    await usdc.connect(bider).approve(market.address, MaxUint256);
    await expect(market.connect(bider).purchase(skin.address, 6)).to.not.reverted;
    expect(await usdc.connect(bider).balanceOf(bider.address)).to.eq(mintAmount.sub(bidPrice));
    expect(await usdc.connect(seller).balanceOf(seller.address)).to.eq(mintAmount.add(bidPrice));
  });

  it('Market: Should listing for sell 2', async () => {
    await expect(market.connect(bider).listingForSell(skin.address, 6, bidPrice)).to.not.reverted;
    await usdc.connect(seller).approve(market.address, MaxUint256);
    await expect(market.connect(seller).purchase(skin.address, 6)).to.not.reverted;
    expect(await usdc.connect(bider).balanceOf(bider.address)).to.eq(mintAmount);
    expect(await usdc.connect(seller).balanceOf(seller.address)).to.eq(mintAmount);
  });

  it('Market: Should create auction', async () => {
    await expect(
      market.connect(seller).createAuction(skin.address, 6, bidPrice, Math.floor(Date.now() / 1000 + 30), 60)
    ).to.not.reverted;
  });

  it('Market: Place bid revert with not exits auction', async () => {
    await expect(market.connect(bider).placeBid(skin.address, 1, bidPrice)).to.revertedWith('Auction is not available');
  });

  it('Market: Place bid revert with approve', async () => {
    await market.connect(bider).createAuction(skin.address, 1, bidPrice, Math.floor(Date.now() / 1000 + 30), 60);
    await expect(market.connect(bider).placeBid(skin.address, 1, bidPrice)).to.revertedWith(
      'The auction should have an seller different from the sender'
    );
  });

  it('Market: Place bid revert with owner', async () => {
    await usdc.connect(bider).approve(market.address, MaxUint256);
    await expect(market.connect(bider).placeBid(skin.address, 1, bidPrice)).to.revertedWith(
      'The auction should have an seller different from the sender'
    );
  });

  it('Market: Should place bid', async () => {
    await delay(30);
    await expect(market.connect(bider).placeBid(skin.address, 6, bidPrice)).to.not.reverted;
  }).timeout(40000);

  it('Market: Should cancel auction', async () => {
    await expect(market.connect(seller).cancelAuction(skin.address, 6)).to.not.reverted;
  });

  it('Market: Should create auction 2', async () => {
    await expect(
      market.connect(seller).createAuction(skin.address, 6, bidPrice, Math.floor(Date.now() / 1000 + 30), 60)
    ).to.not.reverted;
  });

  it('Market: Should place bid', async () => {
    await delay(30);
    await expect(market.connect(bider).placeBid(skin.address, 6, bidPrice)).to.not.reverted;
  }).timeout(40000);

  it('Market: Should complete', async () => {
    await delay(70);
    await expect(market.connect(bider).claimAfterAuction(skin.address, 6)).to.not.reverted;
    expect(await skin.connect(bider).ownerOf(6)).to.equal(bider.address);
    expect(await usdc.connect(bider).balanceOf(bider.address)).to.eq(mintAmount.sub(bidPrice));
    expect(await usdc.connect(seller).balanceOf(seller.address)).to.eq(mintAmount.add(bidPrice));
  }).timeout(80000);

  it('Market: Should set fee', async () => {
    await expect(market.connect(bider).setTransactionFee(fee)).to.not.reverted;
    expect(await market.connect(bider).transactionFee()).to.eq(fee);
  });

  it('Market: Should place bid before set transaction fee', async () => {
    await market.connect(bider).createAuction(skin.address, 6, bidPrice, Math.floor(Date.now() / 1000 + 50), 60);
    await usdc.connect(seller).approve(market.address, MaxUint256);
    await delay(50);
    await expect(market.connect(seller).placeBid(skin.address, 6, bidPrice)).to.not.reverted;
  }).timeout(60000);

  it('Market: Should complete before set transaction fee', async () => {
    const feeAmount = bidPrice.mul(fee).div(1e6);
    await delay(70);
    await expect(market.connect(bider).claimAfterAuction(skin.address, 6)).to.not.reverted;
    expect(await skin.connect(seller).ownerOf(6)).to.equal(seller.address);
    expect(await usdc.connect(bider).balanceOf(bider.address)).to.eq(mintAmount.sub(feeAmount));
    expect(await usdc.connect(seller).balanceOf(seller.address)).to.eq(mintAmount);
    expect(await usdc.connect(seller).balanceOf(market.address)).to.eq(feeAmount);
  }).timeout(80000);

  it('Market: Should withdraw fee', async () => {
    await expect(market.connect(bider).withdrawFee(seller.address)).to.not.reverted;
    expect(await usdc.connect(bider).balanceOf(bider.address)).to.eq(mintAmount);
    expect(await usdc.connect(bider).balanceOf(market.address)).to.eq(parseUnits('0', 18));
  });
});

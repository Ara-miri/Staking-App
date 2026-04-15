export const CONFIG = {
  TOKEN_ADDRESS: "0x316eB7De3b1B7b2Cf5C8F948bFd5059c2a76Cbc8",
  STAKING_ADDRESS: "0xa31FA4c9beF2DfF105F89FA64bA5Cc64BAcF952E",
  BSC_TESTNET_CHAIN_ID: 97,
  BSC_TESTNET_PARAMS: {
    chainId: "0x61",
    chainName: "BNB Smart Chain Testnet",
    nativeCurrency: { name: "BNB", symbol: "tBNB", decimals: 18 },
    rpcUrls: ["https://data-seed-prebsc-1-s1.binance.org:8545/"],
    blockExplorerUrls: ["https://testnet.bscscan.com"],
  },
};

export const STAKING_ABI = [
  "function stakedBalance(address) view returns (uint256)",
  "function earned(address) view returns (uint256)",
  "function timeUntilUnlock(address) view returns (uint256)",
  "function lockUntil(address) view returns (uint256)",
  "function totalStaked() view returns (uint256)",
  "function rewardPoolBalance() view returns (uint256)",
  "function rewardRate() view returns (uint256)",
  "function lockPeriod() view returns (uint256)",
  "function paused() view returns (bool)",
  "function getUserInfo(address) view returns (uint256 staked, uint256 rewards, uint256 unlock, uint256 secondsLeft)",
  "function stake() payable",
  "function withdraw(uint256 amount)",
  "function claimRewards()",
  "function emergencyWithdraw()",
];

export const TOKEN_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
];

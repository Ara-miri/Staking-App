import { CONFIG, STAKING_ABI, TOKEN_ABI } from "./config.js";
// ─── State ────────────────────────────────────────────────────────────────────
let provider, signer, stakingContract, tokenContract;
let userAddress = null;
let pollTimer = null;

// ─── DOM helpers ──────────────────────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const fmt = (wei, dec = 4) =>
  parseFloat(ethers.utils.formatEther(wei)).toFixed(dec);
const fmtSecs = (s) => {
  s = Number(s);
  if (s <= 0) return "Unlocked";
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  return `${d}d ${h}h ${m}m`;
};
const showToast = (msg, type = "success") => {
  const t = $("toast");
  t.textContent = msg;
  t.className = `toast show ${type}`;
  clearTimeout(t._timer);
  t._timer = setTimeout(() => t.classList.remove("show"), 4000);
};

const setLoading = (btnId, loading) => {
  const btn = $(btnId);
  btn.disabled = loading;
  btn.dataset.original = btn.dataset.original || btn.innerHTML;
  btn.innerHTML = loading
    ? `<span class="spinner"></span> Processing…`
    : btn.dataset.original;
};

// ─── Wallet connection ────────────────────────────────────────────────────────
async function connectWallet() {
  if (!window.ethereum) {
    showToast("MetaMask not found. Please install it.", "error");
    return;
  }
  try {
    provider = new ethers.providers.Web3Provider(window.ethereum);
    await provider.send("eth_requestAccounts", []);
    await checkNetwork();
  } catch (e) {
    showToast(e.message || "Connection rejected", "error");
  }
}

async function disconnectWallet() {
  userAddress = null;
  provider = signer = stakingContract = tokenContract = null;
  clearInterval(pollTimer);
  setWalletUI(false);
  setDashboardVisible(false);
}

async function checkNetwork() {
  const network = await provider.getNetwork();
  const btn = $("walletBtn");
  if (network.chainId !== CONFIG.BSC_TESTNET_CHAIN_ID) {
    btn.textContent = "Wrong Network";
    btn.classList.add("wrong-network");
    btn.onclick = switchNetwork;
    showToast("Please switch to BSC Testnet", "error");
    setDashboardVisible(false);
    return;
  }
  btn.classList.remove("wrong-network");
  btn.onclick = disconnectWallet;
  signer = provider.getSigner();
  userAddress = await signer.getAddress();
  stakingContract = new ethers.Contract(
    CONFIG.STAKING_ADDRESS,
    STAKING_ABI,
    signer,
  );
  tokenContract = new ethers.Contract(CONFIG.TOKEN_ADDRESS, TOKEN_ABI, signer);
  setWalletUI(true);
  setDashboardVisible(true);
  await refreshAll();
  startPolling();
}

async function switchNetwork() {
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: "0x61" }],
    });
  } catch (e) {
    if (e.code === 4902) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [CONFIG.BSC_TESTNET_PARAMS],
      });
    }
  }
}

function setWalletUI(connected) {
  const btn = $("walletBtn");
  const addr = $("walletAddress");
  if (connected) {
    const short = `${userAddress.slice(0, 6)}…${userAddress.slice(-4)}`;
    btn.innerHTML = `<span class="dot connected"></span> ${short}`;
    btn.onclick = disconnectWallet;
    addr.textContent = short;
    $("headerActions").classList.add("connected");
  } else {
    btn.innerHTML = "Connect Wallet";
    btn.onclick = connectWallet;
    addr.textContent = "";
    $("headerActions").classList.remove("connected");
  }
}

function setDashboardVisible(visible) {
  $("dashboard").style.display = visible ? "block" : "none";
  $("connectCta").style.display = visible ? "none" : "flex";
}

// ─── Data refresh ─────────────────────────────────────────────────────────────
async function refreshAll() {
  if (!userAddress) return;
  try {
    const [
      info,
      bnbBalance,
      tokenBalance,
      totalStaked,
      poolBalance,
      rate,
      period,
    ] = await Promise.all([
      stakingContract.getUserInfo(userAddress),
      provider.getBalance(userAddress),
      tokenContract.balanceOf(userAddress),
      stakingContract.totalStaked(),
      stakingContract.rewardPoolBalance(),
      stakingContract.rewardRate(),
      stakingContract.lockPeriod(),
    ]);

    // Stats cards
    $("statTotalStaked").textContent = `${fmt(totalStaked, 3)} tBNB`;
    $("statRewardPool").textContent = `${fmt(poolBalance, 0)} SRT`;
    $("statRewardRate").textContent = `${rate.toString()} SRT/BNB/day`;
    $("statLockPeriod").textContent = fmtSecs(period.toNumber());
    // User panel
    $("userBnbBalance").textContent = `${fmt(bnbBalance, 4)} tBNB`;
    $("userSrtBalance").textContent = `${fmt(tokenBalance, 4)} SRT`;
    $("userStaked").textContent = `${fmt(info.staked, 4)} tBNB`;
    $("userRewards").textContent = `${fmt(info.rewards, 4)} SRT`;

    // Lock status
    const secs = info.secondsLeft.toNumber();
    $("lockTimer").textContent = fmtSecs(secs);
    const lockBadge = $("lockBadge");
    if (secs <= 0) {
      lockBadge.textContent = "Unlocked";
      lockBadge.className = "badge unlocked";
    } else {
      lockBadge.textContent = "Locked";
      lockBadge.className = "badge locked";
    }

    // Withdraw max hint
    $("withdrawHint").textContent = info.staked.gt(0)
      ? `Max: ${fmt(info.staked, 4)} tBNB`
      : "";
  } catch (e) {
    console.error("Refresh error:", e);
  }
}

function startPolling() {
  clearInterval(pollTimer);
  pollTimer = setInterval(refreshAll, 10_000);
}

// ─── Actions ─────────────────────────────────────────────────────────────────
async function doStake() {
  const input = $("stakeInput").value.trim();
  if (!input || isNaN(input) || +input <= 0) {
    showToast("Enter a valid BNB amount", "error");
    return;
  }
  setLoading("stakeBtn", true);
  try {
    const value = ethers.utils.parseEther(input);
    const tx = await stakingContract.stake({ value });
    showToast("Transaction sent — waiting for confirmation…");
    await tx.wait();
    showToast(`Staked ${input} tBNB successfully!`);
    $("stakeInput").value = "";
    await refreshAll();
  } catch (e) {
    showToast(parseError(e), "error");
  } finally {
    setLoading("stakeBtn", false);
  }
}

async function doWithdraw() {
  const input = $("withdrawInput").value.trim();
  if (!input || isNaN(input) || +input <= 0) {
    showToast("Enter a valid BNB amount", "error");
    return;
  }
  setLoading("withdrawBtn", true);
  try {
    const amount = ethers.utils.parseEther(input);
    const tx = await stakingContract.withdraw(amount);
    showToast("Withdrawal submitted — waiting…");
    await tx.wait();
    showToast(`Withdrew ${input} tBNB + rewards!`);
    $("withdrawInput").value = "";
    await refreshAll();
  } catch (e) {
    showToast(parseError(e), "error");
  } finally {
    setLoading("withdrawBtn", false);
  }
}

async function doClaimRewards() {
  setLoading("claimBtn", true);
  try {
    const tx = await stakingContract.claimRewards();
    showToast("Claim submitted — waiting…");
    await tx.wait();
    showToast("Rewards claimed!");
    await refreshAll();
  } catch (e) {
    showToast(parseError(e), "error");
  } finally {
    setLoading("claimBtn", false);
  }
}

async function doEmergencyWithdraw() {
  if (!confirm("Emergency withdraw forfeits all accrued rewards. Continue?"))
    return;
  setLoading("emergencyBtn", true);
  try {
    const tx = await stakingContract.emergencyWithdraw();
    showToast("Emergency withdrawal submitted — waiting…");
    await tx.wait();
    showToast("Emergency withdrawal complete. No rewards transferred.");
    await refreshAll();
  } catch (e) {
    showToast(parseError(e), "error");
  } finally {
    setLoading("emergencyBtn", false);
  }
}

// ─── Error parser ─────────────────────────────────────────────────────────────
function parseError(e) {
  const msg = e?.error?.message || e?.reason || e?.message || "Unknown error";
  if (msg.includes("WithdrawalTimelocked")) return "Funds are still locked.";
  if (msg.includes("InsufficientBalance"))
    return "Insufficient staked balance.";
  if (msg.includes("InsufficientRewardPool")) return "Reward pool is empty.";
  if (msg.includes("AmountMustBeGreaterThanZero")) return "Amount must be > 0.";
  if (msg.includes("Pausable: paused") || msg.includes("EnforcedPause"))
    return "Contract is paused.";
  if (msg.includes("user rejected")) return "Transaction rejected.";
  return msg.slice(0, 100);
}

// ─── MetaMask event listeners ─────────────────────────────────────────────────
if (window.ethereum) {
  window.ethereum.on("accountsChanged", (accounts) => {
    if (accounts.length === 0) disconnectWallet();
    else {
      userAddress = accounts[0];
      checkNetwork();
    }
  });
  window.ethereum.on("chainChanged", () => {
    provider = new ethers.providers.Web3Provider(window.ethereum);
    checkNetwork();
  });
}

// ─── Max buttons ──────────────────────────────────────────────────────────────
async function setMaxStake() {
  const bal = await provider.getBalance(userAddress);
  const gas = ethers.utils.parseEther("0.002");
  const max = bal.gt(gas) ? bal.sub(gas) : ethers.constants.Zero;
  $("stakeInput").value = ethers.utils.formatEther(max);
}
async function setMaxWithdraw() {
  const info = await stakingContract.getUserInfo(userAddress);
  $("withdrawInput").value = ethers.utils.formatEther(info.staked);
}

// ─── Init ─────────────────────────────────────────────────────────────────────
$("walletBtn").onclick = connectWallet;
$("stakeBtn").onclick = doStake;
$("withdrawBtn").onclick = doWithdraw;
$("claimBtn").onclick = doClaimRewards;
$("emergencyBtn").onclick = doEmergencyWithdraw;
$("maxStakeBtn").onclick = setMaxStake;
$("maxWithdrawBtn").onclick = setMaxWithdraw;
$("connectCtaBtn").onclick = connectWallet;

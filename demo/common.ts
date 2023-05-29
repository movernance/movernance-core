import {
  normalizeSuiObjectId,
  SuiTransactionBlockResponse,
  Connection,
  Ed25519Keypair,
  fromB64,
  JsonRpcProvider,
  RawSigner,
  TransactionBlock,
  TransactionBlockInput,
} from "@mysten/sui.js";
import { MoveCallTransaction } from "@mysten/sui.js/src/builder/Transactions";
const { execSync } = require("child_process");
require("dotenv").config();

export const connection = new Connection({
  fullnode: process.env.SUI_RPC_URL!,
  faucet: process.env.FAUCET_URL,
});
// const connection = devnetConnection;
export const provider = new JsonRpcProvider(connection);
const keypairseed = process.env.KEY_PAIR_SEED;

const keypair = Ed25519Keypair.fromSecretKey(
  Uint8Array.from(Buffer.from(keypairseed!, "hex"))
);
export const signer = new RawSigner(keypair, provider);
export const gasBudget = 100000;

export async function publish(
  packagePath: string,
  signer: RawSigner
): Promise<SuiTransactionBlockResponse> {
  const compiledModulesAndDeps = JSON.parse(
    execSync(`sui move build --dump-bytecode-as-base64 --path ${packagePath}`, {
      encoding: "utf-8",
    })
  );
  const tx = new TransactionBlock();
  const [upgradeCap] = tx.publish( {
      modules: compiledModulesAndDeps.modules.map((m: any) => Array.from(fromB64(m))),
      dependencies: compiledModulesAndDeps.dependencies.map((addr: string) => normalizeSuiObjectId(addr)),
    }
  );
  tx.transferObjects([upgradeCap], tx.pure(await signer.getAddress()));
  const publishTxn = await signer.signAndExecuteTransactionBlock({
    transactionBlock: tx,
    options: {
      showInput: true,
      showEffects: true,
      showEvents: true,
      showObjectChanges: true,
    },
  });
  console.log("publishTxn", JSON.stringify(publishTxn, null, 2));
  return publishTxn;
}

export async function sendTx(
  tx: TransactionBlock,
  signer: RawSigner
): Promise<SuiTransactionBlockResponse> {
  const txnRes = await signer.signAndExecuteTransactionBlock({
    transactionBlock: tx,
    options: {
      showInput: true,
      showEffects: true,
      showEvents: true,
      showObjectChanges: true,
    },
  });
  // console.log('txnRes', JSON.stringify(txnRes, null, 2));
  if (txnRes.effects?.status.status !== "success") {
    console.log("txnRes", JSON.stringify(txnRes, null, 2));
    throw new Error(
      `transaction failed with error: ${txnRes.effects?.status.error}}`
    );
  }
  return txnRes;
}

export async function prepareAmount(
  coinType: string,
  amount: bigint,
  sender: RawSigner
): Promise<{ tx: TransactionBlock; txCoin: any }> {
  const senderAddr = await sender.getAddress();
  const isNative = coinType === "0x2::sui::SUI";
  let tx = new TransactionBlock();
  if (isNative) {
    const [txCoin] = tx.splitCoins(tx.gas, [tx.pure(amount)]);
    return { tx, txCoin };
  }
  const { success, coins, totalAmount } = await getCoinsByAmount(
    senderAddr,
    coinType,
    amount
  );
  console.log({ success, coins, totalAmount });
  if (!success) {
    throw new Error(`not enough ${coinType}`);
  }
  let coin = tx.object(coins[0]);
  if (coins.length > 1) {
    tx.mergeCoins(
      coin,
      coins.slice(1).map((c) => tx.object(c))
    );
  }
  const [txCoin] = tx.splitCoins(coin, [tx.pure(amount.toString())]);
  return { tx, txCoin };
}

// get coins whose value sum is greater than or equal to amount
async function getCoinsByAmount(
  owner: string,
  coinType: string,
  amount: bigint
): Promise<{ success: boolean; coins: string[]; totalAmount: bigint }> {
  if (amount <= 0n) {
    throw new Error("amount must be greater than 0");
  }
  let coins: string[] = [];
  let totalAmount = 0n;
  let cursor: string | null = null;
  while (true) {
    let res = await provider.getCoins({
      owner,
      coinType,
      cursor,
    });
    for (const coin of res.data) {
      coins.push(coin.coinObjectId);
      totalAmount += BigInt(coin.balance);
      if (totalAmount >= amount) {
        return { success: true, coins, totalAmount };
      }
    }
    if (!res.hasNextPage) {
      return { success: false, coins, totalAmount };
    }
  }
}

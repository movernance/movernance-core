import {
  SuiObjectChangeCreated,
  SuiObjectChangePublished, SuiObjectResponse,
  TransactionBlock,
} from "@mysten/sui.js";
import path from "path";
import {
  connection,
  gasBudget,
  prepareAmount,
  provider,
  publish,
  sendTx,
  signer,
} from "./common";
require("dotenv").config();

const CLOCK_ADDR =
  "0x0000000000000000000000000000000000000000000000000000000000000006";

const GOV_TYPE_COIN = 0;
const GOV_TYPE_NFT = 1;

interface AppMeta {
  packageId: string;
  spaceStoreId: string;
}

let tx = new TransactionBlock();

async function publishMovernance(): Promise<AppMeta> {
  const publishTxn = await publish(
    path.join(__dirname, "../packages/movernance"),
    signer
  );
  const moduleId = (
    publishTxn.objectChanges!.filter(
      (o) => o.type === "published"
    )[0] as SuiObjectChangePublished
  ).packageId;
  const spaceStoreId = (
    publishTxn.objectChanges!.filter(
      (o) =>
        o.type === "created" &&
        o.objectType.endsWith("::movernance::SpaceStore")
    )[0] as SuiObjectChangeCreated
  ).objectId;
  return {
    packageId: moduleId,
    spaceStoreId,
  };
}

async function interact_token_gov(params: AppMeta) {
  const { packageId, spaceStoreId } = params;
  // === create space
  const metadata = {
    Website: "https://movernance.org",
    Twitter: "@movernance",
    Discord: "https://discord.gg/4Z3Q2Z8",
  };
  const proposeCoinType = "0x2::sui::SUI";
  const voteCoinType = "0x2::sui::SUI";
  const rewardCoinType = "0x2::sui::SUI";
  tx = new TransactionBlock();
  tx.moveCall({
    target: `${packageId}::movernance::create_space`,
    typeArguments: [proposeCoinType, voteCoinType],
    arguments: [
      tx.object(spaceStoreId),
      tx.pure("example space" + Date.now()),
      tx.pure("example space description"),
      tx.pure(
        "https://images.unsplash.com/photo-1444703686981-a3abbc4d4fe3?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=2070&q=80"
      ),
      tx.pure(JSON.stringify(metadata)),
      tx.pure("100"),
      tx.pure(GOV_TYPE_COIN),  // gov_type, 0 means token gov
    ],
  });
  const createSpaceTxn = await sendTx(tx, signer);
  console.log("createSpaceTxn", JSON.stringify(createSpaceTxn, null, 2));
  const spaceId = (
    createSpaceTxn.objectChanges!.filter(
      (o) =>
        o.type === "created" &&
        o.objectType.includes("::movernance::GovSpace")
    )[0] as SuiObjectChangeCreated
  ).objectId;
  console.log(`spaceId: ${spaceId}`);
  // === create proposal
  // get propose coin and threshold
  const spaceObj = await provider.getObject({
    id: spaceId,
    options: {
      showContent: true,
    },
  });
  console.log(`spaceObj: ${JSON.stringify(spaceObj, null, 2)}`);
  // extract from string like '0x31777bfdc652e67e8ea37856c75ede5229d88085::movernance::TokenGovSpace<0x2::sui::SUI, 0x2::sui::SUI>'
  const proposeThreshold = BigInt(
    parseInt((spaceObj.data!.content as any).fields.propose_threshold)
  );
  let prepareAmountRes = await prepareAmount(
    proposeCoinType,
    proposeThreshold,
    signer
  );
  tx = prepareAmountRes.tx;
  tx.moveCall({
    target: `${packageId}::movernance::create_token_gov_proposal`,
    typeArguments: [proposeCoinType, voteCoinType],
    arguments: [
      tx.object(spaceId),
      prepareAmountRes.txCoin,
      tx.pure("example proposal"),
      tx.pure("example proposal body"),
      tx.pure(Date.now()), // start from now
      tx.pure(Date.now() + 86400 * 1000), // one day later
      tx.pure("10"),
      tx.pure(CLOCK_ADDR),
    ],
  });
  const createProposalTxn = await sendTx(tx, signer);
  console.log("createProposalTxn", JSON.stringify(createProposalTxn, null, 2));
  const proposalId = (
    createProposalTxn.objectChanges!.filter(
      (o) =>
        o.type === "created" &&
        o.objectType.includes("movernance::GovProposal")
    )[0] as SuiObjectChangeCreated
  ).objectId;
  // === vote
  const vote_num = 1;
  prepareAmountRes = await prepareAmount(
    voteCoinType,
    BigInt(vote_num),
    signer
  );
  tx = prepareAmountRes.tx;
  tx.moveCall({
    target: `${packageId}::movernance::vote_with_token`,
    typeArguments: [proposeCoinType, voteCoinType],
    arguments: [
      tx.object(proposalId),
      prepareAmountRes.txCoin,
      tx.pure(true),
      tx.pure(CLOCK_ADDR),
    ],
  });
  const voteTxn = await sendTx(tx, signer);
  console.log("voteTxn", JSON.stringify(voteTxn, null, 2));
  // === create reward
  const reward_num = 2;
  prepareAmountRes = await prepareAmount(
    rewardCoinType,
    BigInt(reward_num),
    signer
  );
  tx = prepareAmountRes.tx;
  tx.moveCall({
    target: `${packageId}::movernance::create_reward`,
    typeArguments: [proposeCoinType, voteCoinType, rewardCoinType],
    arguments: [
      tx.object(proposalId),
      prepareAmountRes.txCoin,
      tx.pure(true),
      tx.pure(CLOCK_ADDR),
    ],
  });
  const rewardTxn = await sendTx(tx, signer);
  console.log("rewardTxn", JSON.stringify(rewardTxn, null, 2));
  const rewardId = (
    rewardTxn.objectChanges!.filter(
      (o) => o.type === "created" && o.objectType.includes("movernance::Reward")
    )[0] as SuiObjectChangeCreated
  ).objectId;
  console.log(`rewardId: ${rewardId}`);
  // add reward
  prepareAmountRes = await prepareAmount(
    rewardCoinType,
    BigInt(reward_num),
    signer
  );
  tx = prepareAmountRes.tx;
  tx.moveCall({
    target: `${packageId}::movernance::add_reward`,
    typeArguments: [proposeCoinType, voteCoinType, rewardCoinType],
    arguments: [
      tx.object(proposalId),
      tx.object(rewardId),
      prepareAmountRes.txCoin,
      tx.pure(CLOCK_ADDR),
    ],
  });
  const addRewardTxn = await sendTx(tx, signer);
  console.log("addRewardTxn", JSON.stringify(addRewardTxn, null, 2));
}

async function get_user_nfts(addr: string, structType: string, n: number): Promise<string[]> {
  let hasNext = true;
  let cursor;
  let result: string[] = [];
  while(hasNext) {
    const nfts = await provider.getOwnedObjects({
      cursor,
      owner: addr,
      filter: {
        StructType: structType,
      },
      options: {
        showType: true,
      }
    });
    console.log(`nfts: ${JSON.stringify(nfts, null, 2)}`);
    const nft_ids = nfts.data.map(nft => nft.data!.objectId);
    result.push(...nft_ids);
    if(result.length >= n) {
      return result.slice(0, n);
    }
    cursor = nfts.nextCursor;
    hasNext = nfts.hasNextPage;
  }
  throw new Error(`not enough nfts, required: ${n}, got: ${result.length}`);
}

async function interact_nft_gov(params: AppMeta) {
  const { packageId, spaceStoreId } = params;
  const addr = await signer.getAddress();
  // === create space
  const metadata = {
    Website: "https://movernance.org",
    Twitter: "@movernance",
    Discord: "https://discord.gg/4Z3Q2Z8",
  };
  const proposeNftType = `${packageId}::test_nft::TestNFT`;
  const voteNftType = `${packageId}::test_nft::TestNFT`;
  const rewardCoinType = "0x2::sui::SUI";
  tx = new TransactionBlock();
  tx.moveCall({
    target: `${packageId}::movernance::create_space`,
    typeArguments: [proposeNftType, voteNftType],
    arguments: [
      tx.object(spaceStoreId),
      tx.pure("example space" + Date.now()),
      tx.pure("example space description"),
      tx.pure(
        "https://images.unsplash.com/photo-1444703686981-a3abbc4d4fe3?ixlib=rb-4.0.3&ixid=MnwxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8&auto=format&fit=crop&w=2070&q=80"
      ),
      tx.pure(JSON.stringify(metadata)),
      tx.pure(3),
      tx.pure(GOV_TYPE_NFT),  // gov_type, 1 means nft gov
    ],
  });
  const createSpaceTxn = await sendTx(tx, signer);
  console.log("createSpaceTxn", JSON.stringify(createSpaceTxn, null, 2));
  const spaceId = (
    createSpaceTxn.objectChanges!.filter(
      (o) =>
        o.type === "created" &&
        o.objectType.includes("::movernance::GovSpace")
    )[0] as SuiObjectChangeCreated
  ).objectId;
  console.log(`spaceId: ${spaceId}`);
  // === create proposal
  // get propose coin and threshold
  const spaceObj = await provider.getObject({
    id: spaceId,
    options: {
      showContent: true,
    },
  });
  console.log(`spaceObj: ${JSON.stringify(spaceObj, null, 2)}`);
  // claim nfts
  tx = new TransactionBlock();
  tx.moveCall({
    target: `${packageId}::test_nft::claim_and_transfer`,
    arguments: [tx.pure(10)],
  });
  const claimNftsTx = await sendTx(tx, signer);
  console.log("claimNftsTx", JSON.stringify(claimNftsTx, null, 2));

  // create proposal
  const proposeThreshold = parseInt((spaceObj.data!.content as any).fields.propose_threshold);
  let nfts = await get_user_nfts(addr, proposeNftType, proposeThreshold);
  tx = new TransactionBlock();
  tx.moveCall({
    target: `${packageId}::movernance::create_nft_gov_proposal`,
    typeArguments: [proposeNftType, voteNftType],
    arguments: [
      tx.object(spaceId),
      tx.makeMoveVec({ objects: nfts.map(nft_id => tx.object(nft_id)) }),
      tx.pure("example proposal"),
      tx.pure("example proposal body"),
      tx.pure(Date.now()), // start from now
      tx.pure(Date.now() + 86400 * 1000), // one day later
      tx.pure(2),
      tx.pure(CLOCK_ADDR),
    ],
  });
  const createProposalTxn = await sendTx(tx, signer);
  console.log("createProposalTxn", JSON.stringify(createProposalTxn, null, 2));
  const proposalId = (
    createProposalTxn.objectChanges!.filter(
      (o) =>
        o.type === "created" &&
        o.objectType.includes("movernance::GovProposal")
    )[0] as SuiObjectChangeCreated
  ).objectId;
  // === vote
  const vote_num = 1;
  let vote_nfts = await get_user_nfts(addr, voteNftType, vote_num);
  tx = new TransactionBlock();
  tx.moveCall({
    target: `${packageId}::movernance::vote_with_nfts`,
    typeArguments: [proposeNftType, voteNftType],
    arguments: [
      tx.object(proposalId),
      tx.makeMoveVec({ objects: vote_nfts.map(nft_id => tx.object(nft_id)) }),
      tx.pure(true),
      tx.pure(CLOCK_ADDR),
    ],
  });
  const voteTxn = await sendTx(tx, signer);
  console.log("voteTxn", JSON.stringify(voteTxn, null, 2));
  // === create reward
  const reward_num = 2;
  let prepareAmountRes = await prepareAmount(
    rewardCoinType,
    BigInt(reward_num),
    signer
  );
  tx = prepareAmountRes.tx;
  tx.moveCall({
    target: `${packageId}::movernance::create_reward`,
    typeArguments: [proposeNftType, voteNftType, rewardCoinType],
    arguments: [
      tx.object(proposalId),
      prepareAmountRes.txCoin,
      tx.pure(true),
      tx.pure(CLOCK_ADDR),
    ],
  });
  const rewardTxn = await sendTx(tx, signer);
  console.log("rewardTxn", JSON.stringify(rewardTxn, null, 2));
  const rewardId = (
    rewardTxn.objectChanges!.filter(
      (o) => o.type === "created" && o.objectType.includes("movernance::Reward")
    )[0] as SuiObjectChangeCreated
  ).objectId;
  console.log(`rewardId: ${rewardId}`);
  // add reward
  prepareAmountRes = await prepareAmount(
    rewardCoinType,
    BigInt(reward_num),
    signer
  );
  tx = prepareAmountRes.tx;
  tx.moveCall({
    target: `${packageId}::movernance::add_reward`,
    typeArguments: [proposeNftType, voteNftType, rewardCoinType],
    arguments: [
      tx.object(proposalId),
      tx.object(rewardId),
      prepareAmountRes.txCoin,
      tx.pure(CLOCK_ADDR),
    ],
  });
  const addRewardTxn = await sendTx(tx, signer);
  console.log("addRewardTxn", JSON.stringify(addRewardTxn, null, 2));
}

function extractTokens(
  str: string
): { proposalToken: string; votingToken: string } | undefined {
  const regex =
    /^0x[a-fA-F0-9]+::[a-zA-Z0-9_]+::[a-zA-Z0-9_]+<([^,]+),\s*([^>]+)>$/;
  const matches = str.match(regex);
  if (matches && matches.length === 3) {
    const [proposalToken, votingToken] = matches
      .slice(1)
      .map((token) => token.trim());
    return { proposalToken, votingToken };
  } else {
    return undefined;
  }
}

async function iterateTable(tableId: string, cb: (callback: SuiObjectResponse) => void) {
  let cursor: string | null = null;
  while (true) {
    const fields = await provider.getDynamicFields({
      parentId: tableId,
      cursor,
    });
    console.log(`fields: ${JSON.stringify(fields, null, 2)}`);
    for (const field of fields.data) {
      const object = await provider.getObject({
        id: field.objectId,
        options: {
          showContent: true,
        },
      });
      console.log(`object: ${JSON.stringify(object, null, 2)}`);
      cb(object);
    }
    if (!fields.hasNextPage) {
      break;
    }
    cursor = fields.nextCursor;
  }
}

async function queries(params: AppMeta) {
  const { packageId, spaceStoreId } = params;
  const spaceStore = await provider.getObject({
    id: spaceStoreId,
    options: {
      showContent: true,
    },
  });
  console.log(`spaceStore: ${JSON.stringify(spaceStore, null, 2)}`);
  const spaces_table_id = (spaceStore.data!.content as any).fields.spaces.fields
    .id.id;
  console.log(`spaces_table_id: ${spaces_table_id}`);
  // get all spaces
  let spaces: string[] = [];
  let cursor: string | null = null;
  while (true) {
    const spaceObjs = await provider.getDynamicFields({
      parentId: spaces_table_id,
      cursor,
    });
    console.log(`spaceObjs: ${JSON.stringify(spaceObjs, null, 2)}`);
    for (const spaceObj of spaceObjs.data) {
      const spaceObjItem = await provider.getObject({
        id: spaceObj.objectId,
        options: {
          showContent: true,
        },
      });
      console.log(`spaceObjItem: ${JSON.stringify(spaceObjItem, null, 2)}`);
      spaces.push((spaceObjItem.data!.content as any).fields.value);
    }
    if (!spaceObjs.hasNextPage) {
      break;
    }
    cursor = spaceObjs.nextCursor;
  }
  // get spaces objects
  const spaceObjects = await provider.multiGetObjects({
    ids: spaces,
    options: {
      showContent: true,
    },
  });
  console.log(`spaceObjects: ${JSON.stringify(spaceObjects, null, 2)}`);
  // get proposeCoinType and voteCoinType
  const tokens = extractTokens((spaceObjects[0].data!.content as any).type);
  console.log(`tokens: ${JSON.stringify(tokens, null, 2)}`);
  // get proposals
  const proposals = (spaceObjects[0].data!.content as any).fields.proposals;
  console.log(`proposals: ${JSON.stringify(proposals, null, 2)}`);
  // get proposal status
  let addr = await signer.getAddress();
  tx = new TransactionBlock();
  tx.moveCall({
    target: `${packageId}::movernance::get_proposal_status`,
    typeArguments: [tokens!.proposalToken, tokens!.votingToken],
    arguments: [tx.object(proposals[0]), tx.pure(CLOCK_ADDR)],
  });
  const statusRes = await provider.devInspectTransactionBlock({
    sender: addr,
    transactionBlock: tx,
  });
  console.log(`statusRes: ${JSON.stringify(statusRes, null, 2)}`);
  const status = (statusRes.results as any)[0].returnValues[0][0];
  // STATUS_VOTING: u8 = 0;
  // STATUS_NOT_ENOUGH_VOTES: u8 = 1;
  // STATUS_SUCCESS: u8 = 2;
  // STATUS_FAIL: u8 = 3;
  console.log(`status: ${status}`);
  // get proposal objects
  const proposalObjects = await provider.multiGetObjects({
    ids: proposals,
    options: {
      showContent: true,
    },
  });
  console.log(`proposalObjects: ${JSON.stringify(proposalObjects, null, 2)}`);
  // get all voters
  const yesVotersTableId = (proposalObjects[0].data!.content as any).fields.yes_voters.fields.id.id;
  const noVotersTableId = (proposalObjects[0].data!.content as any).fields.yes_voters.fields.id.id;
  let votes: any= [];
  await iterateTable(yesVotersTableId, (obj) => {
    votes.push({
      addr: (obj.data!.content as any).fields.name,
      voteAmount: (obj.data!.content as any).fields.value,
      voteYes: true,
    });
  });
  await iterateTable(noVotersTableId, (obj) => {
    votes.push({
      addr: (obj.data!.content as any).fields.name,
      voteAmount: (obj.data!.content as any).fields.value,
      voteYes: false,
    });
  });
  console.log(`votes: ${JSON.stringify(votes, null, 2)}`);
  // get votes of a specific address
  const userYesVoteObj = await provider.getDynamicFieldObject({
    parentId: yesVotersTableId,
    name: {
      type: 'address',
      value: addr,
    },
  });
  const userYesVoteNum = userYesVoteObj ? (userYesVoteObj.data!.content as any).fields.value : 0;
  console.log(`userYesVoteNum: ${userYesVoteNum}`);
}

async function main() {
  console.log("-----start-----");
  const addr = await signer.getAddress();
  console.log(`address: 0x${addr}`);
  const balance = await provider.getBalance({
    owner: addr,
  });
  console.log(`balance: ${JSON.stringify(balance, null, 2)}`);

  // faucet
  if(process.env.REQUEST_SUI) {
    const res = await provider.requestSuiFromFaucet(addr);
    console.log("requestSuiFromFaucet", JSON.stringify(res, null, 2));
  }

  // publish
  const appMeta = await publishMovernance();
  // const appMeta = {
  //   moduleId:
  //     "0x4eab127b2685b4a84d510d02c2fa1d897593135e0ac5ad1105384a9adb703136",
  //   spaceStoreId:
  //     "0x56f0fc772b2316334ac387f2881a5600195193376561ef2a079371d4741f3412",
  // };
  console.log(`appMeta: ${JSON.stringify(appMeta, null, 2)}`);
  await interact_token_gov(appMeta);
  await interact_nft_gov(appMeta);
  await queries(appMeta);
  console.log("-----end-----");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(
      `error ${JSON.stringify(error, null, 2)}, stack: ${error.stack}`
    );
    process.exit(1);
  });

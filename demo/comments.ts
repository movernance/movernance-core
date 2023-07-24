import {
  Option,
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

const MAX_U64 = '0xffffffffffffffff';
const proposalId = '0x34b70d7cd61c2dbd7e33af2c9b9c85b3cb5e94fd7d6716bf9d841563fe7ea31f';

interface AppMeta {
  packageId: string;
  appId: string;
}

let tx = new TransactionBlock();

async function publishComments(): Promise<AppMeta> {
  const publishTxn = await publish(
    path.join(__dirname, "../packages/comments"),
    signer
  );
  const moduleId = (
    publishTxn.objectChanges!.filter(
      (o) => o.type === "published"
    )[0] as SuiObjectChangePublished
  ).packageId;

  // create an app
  tx = new TransactionBlock();
  tx.moveCall({
    target: `${moduleId}::comments::create_app`,
    arguments: [],
  });
  const createAppTxn = await sendTx(tx, signer);
  console.log("createAppTxn", JSON.stringify(createAppTxn, null, 2));
  const appId = (
    createAppTxn.objectChanges!.filter(
      (o) =>
        o.type === "created" &&
        o.objectType.endsWith("::comments::Application")
    )[0] as SuiObjectChangeCreated
  ).objectId;

  return {
    packageId: moduleId,
    appId,
  };
}

async function interact(params: AppMeta) {
  const { packageId, appId } = params;
  // comment
  tx = new TransactionBlock();
  tx.moveCall({
    target: `${packageId}::comments::comment`,
    arguments: [
      tx.object(appId),
      tx.pure(proposalId),  // proposal id
      tx.pure('hello world'), // content
      tx.pure(MAX_U64), // quote
      tx.pure(CLOCK_ADDR), // clock
    ],
  });
  const commentTxn = await sendTx(tx, signer);
  console.log("commentTxn", JSON.stringify(commentTxn, null, 2));
  // upvote
  tx = new TransactionBlock();
  tx.moveCall({
    target: `${packageId}::comments::vote`,
    arguments: [
      tx.object(appId),
      tx.pure(proposalId),  // proposal id
      tx.pure(0), // quote comment index
      tx.pure(true), // true means upvote, false means downvote
    ]
  });
  const upvoteTxn = await sendTx(tx, signer);
  console.log("upvoteTxn", JSON.stringify(upvoteTxn, null, 2));
}

async function queries(params: AppMeta) {
  const { packageId, appId } = params;
  const app = await provider.getObject({
    id: appId,
    options: {
      showContent: true,
    },
  });
  console.log("app", JSON.stringify(app, null, 2));
  const commentsId = (app.data!.content as any).fields.comments.fields
    .id.id;
  // get comments by proposal id
  const comments = await provider.getDynamicFieldObject({
    parentId: commentsId,
    name: {
      type: '0x2::object::ID',
      value: proposalId,
    },
  });
  console.log("comments", JSON.stringify(comments, null, 2));

  // list all comments
  const commentObjectVecId = (comments.data!.content as any).fields.value.fields.contents.fields.id.id;
  let cursor: string | null = null;
  while (true) {
    const commentObjs = await provider.getDynamicFields({
      parentId: commentObjectVecId,
      cursor,
    });
    console.log(`commentObjs: ${JSON.stringify(commentObjs, null, 2)}`);
    for (const commentObj of commentObjs.data) {
      const commentObjItem = await provider.getObject({
        id: commentObj.objectId,
        options: {
          showContent: true,
        },
      });
      console.log(`commentObjItem: ${JSON.stringify(commentObjItem, null, 2)}`);
    }
    if (!commentObjs.hasNextPage) {
      break;
    }
    cursor = commentObjs.nextCursor;
  }

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
  const appMeta = await publishComments();
  // const appMeta = {
  //   "packageId": "0xe48b7e41a2613c5d83540becb068420d7b7a65107a67a1ad864cb02ba427133d",
  //   "appId": "0x1431f8f26b2bb552d423c277ae4718cfddd686c1e1ab6ea6586891c22ce2bf40"
  // };
  console.log(`appMeta: ${JSON.stringify(appMeta, null, 2)}`);
  await interact(appMeta);
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

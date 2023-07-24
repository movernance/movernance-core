# Movernance

https://movernance.com/

## Mainnet Contract Address

Movernance:

```
{
  "packageId": "0x13013147189e990360ba0df3a47de7ae54d1fab09c4f6b61c9bcd6d14d1cebc3",
  "spaceStoreId": "0x939c394e46e1031691550a2a1328ee41961119dc610bfe98cb373c1bd4bbcd1f"
}
```

https://suiexplorer.com/object/0x13013147189e990360ba0df3a47de7ae54d1fab09c4f6b61c9bcd6d14d1cebc3?network=mainnet

Comments:

```
{
  "packageId": "0xced260d5f9ded3e149751ed4c86d2748595ddeafb53a2a4b307fd66b36d253da",
  "appId": "0x4e31f092f2a62016d897130e7fdb42f8bbdca9a6be87be6455a30ae373b05022"
}
```

## Development Quick Start

```bash
# install sui cli: <https://docs.sui.io/build/install>
# check sui installed
$ sui -V
sui 1.0.0-7a78de8e28

# install `Task`, refer: https://taskfile.dev/installation/

$ task test -f
task: [test] sui move test
INCLUDING DEPENDENCY Sui
INCLUDING DEPENDENCY MoveStdlib
BUILDING movernance
INCLUDING DEPENDENCY Sui
INCLUDING DEPENDENCY MoveStdlib
BUILDING movernance
Running Move unit tests
[ PASS    ] 0x0::movernance_tests::test_nft_gov_success
[ PASS    ] 0x0::movernance_tests::test_token_gov_success
Test result: OK. Total tests: 2; passed: 2; failed: 0

# install dependencies
$ yarn install

$ cp .env.example .env
# edit .env, replace KEY_PAIR_SEED with a random hex string
# you can generate it with command `openssl rand -hex 32`

# run demo
$ task demo -f
yarn run v1.22.19
-----start-----
address: 0x15f4d7062df50ed70f7770fbcb124d5de305fc9bee6d2e825f277187116f2e4c
...
userYesVoteNum: 1
-----end-----
✨  Done in 39.63s.

# check the explorer: <https://suiexplorer.com/address/0x15f4d7062df50ed70f7770fbcb124d5de305fc9bee6d2e825f277187116f2e4c?network=devnet>
# replace the address with your own
```

You can check the GitHub actions for more details.

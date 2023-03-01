# A Simple Smart Contract in Sway

From [this post](https://forum.fuel.network/t/how-to-write-a-smart-contract-on-sway-with-transfer-deposit-and-other-basic-functions/1274) of the Fuel Forum.

## Install all the things

The easiest way to have everything simulateously up to date + easy switching between versions is with [fuelup](https://fuellabs.github.io/fuelup/master/). 

To use Sway, the Rust toolchain must be installed. This can be done with [rustup](https://rustup.rs/). 

## Write Smart Contract

### Initialize project

``` forc new money-box ```

### Functions

The Smart contract has 3 functions:
- deposit
- withdraw
- balance

The Smart contract holds a StorageMap in storage where the amount (in u64) per asset per user is stored. A key for this map is formed by (Address, ContractId). 

There is 1 custom error called InsufficientBalance. 

#### *Deposit*

Input: none. Output: none. 

Functionality: takes msg_amount, msg_asset_id as well as the address of the sender. The amount for the relevant asset is increased.

Errors: if sender address cannot be retrieved, execution is reverted. 

#### *Withdraw*

Input: asset_id, amount. Ouput: none. 

Functionality: takes the address of the sender and checks for the given asset if there is enough balance to fo the withdraw. If that is the case, the amount of asset is transferred and the balance in storage is updated. 

Errors:
- if sender address cannot be retrieved, execution is reverted. 
- if balance of relevant asset is too low Error InsufficientBalance is thrown

#### *Balance*

Input: address, asset_id. Output: amount.

Functionality: returns balance of specified user and asset_id. If no deposit has been done, return 0.

Errors: none. 

## Build 

```
forc build
```

Successful build gives something like:

```
  WARNING! unused manifest key: project.target
  Compiled library "core".
  Compiled library "std".
  Compiled contract "money-box".
  Bytecode size is 5316 bytes.
```


## Add tests

Create a testing environment:

```
cargo generate --init fuellabs/sway templates/sway-test-rs --name money_box --force
```

Within the test folder, create the folders:
local_test - for tests that run on a local node
testnet_tests - for tests that run on a testnet node
utils - for helpful functions
artefacts - for contract ABIs

### Test Token 
In artefacts, create a folder token and [these files](https://github.com/sway-gang/money-box/tree/master/tests/artefacts/token). You can also create a Token yourself, this is only for testing purposes so we have something to deposit and withdraw. 


### Test Utils
In utils we'll add code that should abstract away any complexity.

First for the Token. Create a file `number_utils.rs` and add:
```rust
pub fn parse_units(num: u64, decimals: u8) -> u64 {
  num * 10u64.pow(decimals as u32)
}

pub fn format_units(num: u64, decimals: u8) -> u64 {
  num / 10u64.pow(decimals as u32)
}
```

Then create a file `token_utils.rs`.
We'll be using psuedo random numbers and will need to install the respective library: `cargo add rand`. 

The code for this file is:
```rust
use fuels::prelude::*;
use rand::prelude::Rng;
use number_utils::parse_units;

abigen!(Contract(name = "TokenContract", abi = "tests/artefacts/token/token_contract-abi.json"));

pub struct DeployTokenConfig {
  pub name: String,
  pub symbol: String,
  pub decimals: u8,
  pub mint_amount: u64,
}

pub async fn get_token_contract_instance(
  wallet: &WalletUnlocked,
  deploy_config: &DeployTokenConfig,
) -> TokenContract {
  let mut name = deploy_config.name.clone();
  let mut symbol = deploy_config.symbol.clone();
  let decimals = deploy_config.decimals;

  let mut rng = rand::thread_rng();
  let salt = rng.gen::<[u8; 32]>();

  let id = Contract::deploy_with_parameters(
      "./tests/artefacts/token/token_contract.bin",
      &wallet,
      TxParameters::default(),
      StorageConfiguration::default(),
      Salt::from(salt),
  )
  .await
  .unwrap();

  let instance = TokenContract::new(id, wallet.clone());
  let methods = instance.methods();

  let mint_amount = parse_units(deploy_config.mint_amount, decimals);
  name.push_str(" ".repeat(32 - deploy_config.name.len()).as_str());
  symbol.push_str(" ".repeat(8 - deploy_config.symbol.len()).as_str());

  let config: token_contract_mod::Config = token_contract_mod::Config {
      name: fuels::core::types::SizedAsciiString::<32>::new(name).unwrap(),
      symbol: fuels::core::types::SizedAsciiString::<8>::new(symbol).unwrap(),
      decimals,
  };

  let _res = methods
      .initialize(config, mint_amount, Address::from(wallet.address()))
      .call()
      .await;
  let _res = methods.mint().append_variable_outputs(1).call().await;

  instance
}
```

Finally for the utils, add a file `local_tests_utils.rs', with the following code:

```rust
use fuels::prelude::*;

abigen!(Contract(name = "MoneyBox", abi = "out/debug/money_box-abi.json"));


pub async fn init_wallet() -> WalletUnlocked {
    let mut wallets = launch_custom_provider_and_get_wallets(
        WalletsConfig::new(
            Some(1),             /* Single wallet */
            Some(1),             /* Single coin (UTXO) */
            Some(1_000_000_000), /* Amount per coin */
        ),
        None,
        None,
    )
    .await;
    wallets.pop().unwrap()
}

pub async fn get_money_box_instance(wallet: &WalletUnlocked) -> MoneyBox {
    let id = Contract::deploy(
        "./out/debug/money-box.bin",
        &wallet,
        TxParameters::default(),
        StorageConfiguration::default(),
    )
    .await
    .unwrap();

    MoneyBox::new(id, wallet.clone())
}

pub async fn print_balances(wallet: &WalletUnlocked) {
    let balances = wallet.get_balances().await.unwrap();
    println!("{:#?}\n", balances);
}
```

### Main Test

In `tests/local_tests` create a file `main_test.rs` with the actual test code. This can be the following: 

```rust
use fuels::{
  prelude::CallParameters,
  tx::{Address, AssetId, ContractId},
};

use crate::utils::{
  local_tests_utils::*,
  token_utils::*,
  number_utils::{format_units, parse_units},
};

#[tokio::test]
async fn main_test() {
  //--------------- CREATE WALLET ---------------
  let wallet = init_wallet().await;
  let address = Address::from(wallet.address());
  println!("Wallet address {address}\n");

  //--------------- DEPLOY TOKEN ---------------
  let usdc_config = DeployTokenConfig {
      name: String::from("USD Coin"),
      symbol: String::from("USDC"),
      decimals: 6,
      mint_amount: 10000,
  };

  let token_instance = get_token_contract_instance(&wallet, &usdc_config).await;
  let asset_id = AssetId::from(*token_instance.contract_id().hash());
  let contract_asset_id = ContractId::from(token_instance.contract_id());

  print_balances(&wallet).await;
  let money_box = get_money_box_instance(&wallet).await;

  let methods = money_box.methods();

  let deposit_amount = parse_units(100, usdc_config.decimals);

  // //-----------------------------------------------
  // //first deposit for 100 tokens and check that balance is 100
  let call_params = CallParameters::new(Some(deposit_amount), Some(asset_id), None);
  methods
      .deposit()
      .call_params(call_params)
      .call()
      .await
      .expect("❌ first deposit failed");

  let balance = methods
      .balance(address, contract_asset_id)
      .simulate()
      .await
      .unwrap()
      .value;

  assert_eq!(balance, parse_units(100, usdc_config.decimals));

  let formatted_balance = format_units(balance, usdc_config.decimals);
  println!(
      "✅ first deposit for 100 USDC is done and total balance is {} USDC",
      formatted_balance
  );

  // //-----------------------------------------------
  // // first withdraw 100 tokens and check that balance is 0
  let withdraw_amount = parse_units(100, usdc_config.decimals);
  let call_params = CallParameters::new(Some(withdraw_amount), Some(asset_id), None);
  methods
      .withdraw(contract_asset_id, withdraw_amount)
      .call_params(call_params)
      .estimate_tx_dependencies(None)
      .await
      .unwrap()
      .call()
      .await
      .expect("❌ first withdraw failed");

  let balance = methods
      .balance(Address::from(wallet.address()), contract_asset_id)
      .simulate()
      .await
      .unwrap()
      .value;
  assert_eq!(balance, parse_units(0, usdc_config.decimals));
  let formatted_balance = format_units(balance, usdc_config.decimals);
  println!(
      "✅ first withdraw for 100 USDC is done and total balance is {} USDC",
      formatted_balance
  );

  // //-----------------------------------------------
  // //second deposit for 50 tokens and check that balance is 50
  let deposit_amount = parse_units(50, usdc_config.decimals);
  let call_params = CallParameters::new(Some(deposit_amount), Some(asset_id), None);
  methods
      .deposit()
      .call_params(call_params)
      .call()
      .await
      .expect("❌ second deposit failed");

  let balance = methods
      .balance(Address::from(wallet.address()), contract_asset_id)
      .simulate()
      .await
      .unwrap()
      .value;
  assert_eq!(balance, parse_units(50, usdc_config.decimals));
  let formatted_balance = format_units(balance, usdc_config.decimals);
  println!(
      "✅ second deposit for 50 USDC is done and total balance is {} USDC",
      formatted_balance
  );

  // //-----------------------------------------------
  // //third deposit for 150 tokens and check that balance is 200
  let deposit_amount = parse_units(150, usdc_config.decimals);
  let call_params = CallParameters::new(Some(deposit_amount), Some(asset_id), None);
  methods
      .deposit()
      .call_params(call_params)
      .call()
      .await
      .expect("❌ third deposit failed");

  let balance = methods
      .balance(Address::from(wallet.address()), contract_asset_id)
      .simulate()
      .await
      .unwrap()
      .value;
  assert_eq!(balance, parse_units(200, usdc_config.decimals));
  let formatted_balance = format_units(balance, usdc_config.decimals);
  println!(
      "✅ third deposit for 150 USDC is done and total balance is {} USDC",
      formatted_balance
  );

  //-----------------------------------------------
  // second withdraw for 15 tokens and check that balance is 185
  let withdraw_amount = parse_units(15, usdc_config.decimals);
  let call_params = CallParameters::new(Some(withdraw_amount), Some(asset_id), None);
  methods
      .withdraw(contract_asset_id, withdraw_amount)
      .call_params(call_params)
      .estimate_tx_dependencies(None)
      .await
      .unwrap()
      .call()
      .await
      .expect("❌ first withdraw failed");

  let balance = methods
      .balance(Address::from(wallet.address()), contract_asset_id)
      .simulate()
      .await
      .unwrap()
      .value;
  assert_eq!(balance, parse_units(185, usdc_config.decimals));
  let formatted_balance = format_units(balance, usdc_config.decimals);
  println!(
      "✅ second withdraw for 200 USDC is done and total balance is {} USDC",
      formatted_balance
  );
}
```

### Run Test

Run `cargo test` or to see the logged values, run it in the `.rs` file directly. 

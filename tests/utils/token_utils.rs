use fuels::prelude::*;
use rand::prelude::Rng;
use crate::utils::number_utils::parse_units;
use fuels::types::SizedAsciiString;

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

  let config: Config = Config {
      name: SizedAsciiString::<32>::new(name).unwrap(),
      symbol: SizedAsciiString::<8>::new(symbol).unwrap(),
      decimals,
  };

  let _res = methods
      .initialize(config, mint_amount, Address::from(wallet.address()))
      .call()
      .await;
  let _res = methods.mint().append_variable_outputs(1).call().await;

  instance
}

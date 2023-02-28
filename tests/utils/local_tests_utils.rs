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
contract;

use std::{
    auth::{
        AuthError,
        msg_sender,
    },
    call_frames::{
        msg_asset_id,
    },
    context::{
        msg_amount,
    },
    revert::require,
    token::transfer_to_address
};

storage {
  deposits: StorageMap<(Address, ContractId), u64> = StorageMap {},
}

enum Error {
  InsufficientBalance: (),
}

abi MoneyBox {
  #[storage(write, read)]
  fn deposit();

  #[storage(write, read)]
  fn withdraw(asset_id: ContractId, amount: u64);

  #[storage(read)]
  fn balance(address: Address, asset_id: ContractId) -> u64;
}

/*
returns the address of the sender of the current message

Reverts execution if the sender is not an address
*/
fn get_msg_sender_address_or_panic() -> Address {
  let sender: Result<Identity, AuthError> = msg_sender();
  if let Identity::Address(address) = sender.unwrap() {
    address
  } else {
    revert(0);
  }
}

/*
gets the balance of a user in the contract
If there is no balance for current asset it will return 0
*/
#[storage(read)]
fn internal_balance_or_0(address: Address, asset_id: ContractId) -> u64 {
  let key = (address, asset_id);
  let balanceOption = storage.deposits.get(key);
  balanceOption.unwrap_or(0)
}

impl MoneyBox for Contract {
  /*
  gets the amount and asset Id of the tokens attached to the current message
  gets the address of the sender of the current message
    and then deposits the tokens into the contract by adding the amount to the user’s existing balance

  Errors:
  - if sender address cannot be retrieved, execution is reverted. 
  */
  #[storage(write, read)]
  fn deposit() {
    let amount = msg_amount();
    let asset_id = msg_asset_id();
    let sender_address = get_msg_sender_address_or_panic();

    let current_balance_for_asset = internal_balance_or_0(sender_address, asset_id);
    let new_balance = amount + current_balance_for_asset;
    let key = (sender_address, asset_id);
    storage.deposits.insert(key, new_balance);
  }

  /*
  gets the user’s address
  checks that the user has enough balance to cover the withdrawal
    and then transfers the specified amount of the specified asset to the user’s address. 
    
  If the withdrawal is successful, it updates the user’s balance in the contract.

  Errors:
  - if sender address cannot be retrieved, execution is reverted. 
  - if balance of relevant asset is too low Error InsufficientBalance is thrown
  */
  #[storage(write, read)]
  fn withdraw(asset_id: ContractId, amount: u64) {
    let sender_address = get_msg_sender_address_or_panic();
    let key = (sender_address, asset_id);
    let current_balance_for_asset = internal_balance_or_0(sender_address, asset_id);
    // The balance for asset must be high enough
    require(current_balance_for_asset >= amount, Error::InsufficientBalance);
    
    transfer_to_address(amount, asset_id, sender_address);

    let balance_after = current_balance_for_asset - amount;
    let key = (sender_address, asset_id);
    if balance_after > 0 {
      storage.deposits.insert(key, balance_after);
    } else {
      storage.deposits.insert(key, 0); // should not be possible to get below 0, because of previous check
    }
  }

  /*
  returns the balance of the specified user and asset. If no such balance exists, return 0.
  */
  #[storage(read)]
  fn balance(address: Address, asset_id: ContractId) -> u64 {
    internal_balance_or_0(address, asset_id)
  }
}
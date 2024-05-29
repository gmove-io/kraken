/// This module uses the access apis to stream a coin for a payment.
/// A payment has an amount to be paid at each interval, until the balance is empty.
/// It can be cancelled by the multisig member.

module kraken::payments {
    use std::string::String;

    use sui::transfer::Receiving;
    use sui::balance::Balance;
    use sui::coin::{Self, Coin};
    
    use kraken::access::{Self, Withdraw};
    use kraken::multisig::{Multisig, Action};

    // === Errors ===

    const ECompletePaymentBefore: u64 = 0;
    const EPayTooEarly: u64 = 1;

    // === Structs ===

    // action to be held in a Proposal
    public struct Pay has store {
        // sub action - coin to access (with the right amount)
        withdraw: Withdraw,
        // amount to pay at each due date
        amount: u64,
        // number of epochs between each payment
        interval: u64,
        // address to pay
        recipient: address,
    }

    // balance for a payment is locked and sent automatically from backend
    public struct Stream<phantom C: drop> has key {
        id: UID,
        // remaining balance to be sent
        balance: Balance<C>,
        // amount to pay at each due date
        amount: u64,
        // number of epochs between each payment
        interval: u64,
        // epoch of the last payment
        last_epoch: u64,
        // address to pay
        recipient: address,
    }

    // === Multisig functions ===

    // step 1: propose to create a Stream with a specific amount to be paid at each interval
    public fun propose_pay(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        coin: ID, // must have the total amount to be paid
        amount: u64, // amount to be paid at each interval
        interval: u64, // number of epochs between each payment
        recipient: address,
        ctx: &mut TxContext
    ) {
        let withdraw = access::new_withdraw(vector[coin]);
        let action = Pay { withdraw, amount, interval, recipient };
        multisig.create_proposal(
            action,
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: loop over it in PTB, sends last object from the Send action
    public fun create_stream<C: drop>(
        action: Action<Pay>, 
        multisig: &mut Multisig, 
        received: Receiving<Coin<C>>,
        ctx: &mut TxContext
    ) {
        let Pay { mut withdraw, amount, interval, recipient } = action.unpack_action();
        let coin = withdraw.withdraw(multisig, received);
        withdraw.complete_withdraw();

        let stream = Stream<C> { 
            id: object::new(ctx), 
            balance: coin.into_balance(), 
            amount,
            interval,
            last_epoch: 0,
            recipient 
        };
        transfer::share_object(stream);
    }

    // step 5: backend send the coin to the recipient until balance is empty
    public fun pay<C: drop>(stream: &mut Stream<C>, ctx: &mut TxContext) {
        assert!(ctx.epoch() > stream.last_epoch + stream.interval, EPayTooEarly);

        let amount = if (stream.balance.value() < stream.amount) {
            stream.balance.value()
        } else {
            stream.amount
        };
        let coin = coin::from_balance(stream.balance.split(amount), ctx);

        transfer::public_transfer(coin, stream.recipient);
        stream.last_epoch = ctx.epoch();
    }

    // step 6: destroy the stream when balance is empty
    public fun complete_stream<C: drop>(stream: Stream<C>) {
        let Stream { 
            id, 
            balance, 
            amount: _, 
            interval: _, 
            last_epoch: _, 
            recipient: _ 
        } = stream;
        
        assert!(balance.value() == 0, ECompletePaymentBefore);
        balance.destroy_zero();
        id.delete();
    }

    // step 6 (bis): multisig member can cancel the payment (member only)
    public fun cancel_payment<C: drop>(
        stream: Stream<C>, 
        multisig: &mut Multisig,
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        let Stream { 
            id, 
            balance, 
            amount: _, 
            interval: _, 
            last_epoch: _, 
            recipient: _ 
        } = stream;
        id.delete();

        transfer::public_transfer(
            coin::from_balance(balance, ctx), 
            multisig.addr()
        );
    }
}


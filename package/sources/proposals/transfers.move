/// This module uses the owned apis to transfer assets owned by the multisig.
/// Objects can also be delivered to a single address,
/// meaning that the recipient must claim the objects or the Multisig can retrieve them.

module kraken::transfers {
    use std::string::String;

    use sui::bag::{Self, Bag};
    use sui::transfer::Receiving;

    use kraken::owned::{Self, Withdraw};
    use kraken::multisig::{Multisig, Action};

    // === Errors ===

    const EDifferentLength: u64 = 1;
    const ESendAllAssetsBefore: u64 = 2;
    const EDeliveryNotEmpty: u64 = 3;
    const EWrongDelivery: u64 = 4;

    // === Structs ===

    // action to be held in a Proposal
    public struct Send has store {
        // sub action - owned objects to access
        withdraw: Withdraw,
        // addresses to transfer to
        recipients: vector<address>
    }

    // action to be held in a Proposal
    // a safe send where recipient has to confirm reception
    public struct Deliver has store {
        // sub action - owned objects to access
        withdraw: Withdraw,
        // address to transfer to
        recipient: address
    }

    // shared object holding the objects to be received
    public struct Delivery has key {
        id: UID,
        objects: Bag,
    }

    // cap giving right to withdraw objects from the associated Delivery
    public struct DeliveryCap has key { 
        id: UID,
        delivery_id: ID,
    }

    // === Multisig functions ===

    // step 1: propose to send owned objects
    public fun propose_send(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        objects: vector<ID>,
        recipients: vector<address>,
        ctx: &mut TxContext
    ) {
        assert!(recipients.length() == objects.length(), EDifferentLength);
        let withdraw = owned::new_withdraw(objects);
        let action = Send { withdraw, recipients };
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
    public fun send<T: key + store>(
        action: &mut Action<Send>, 
        multisig: &mut Multisig, 
        received: Receiving<T>
    ) {
        let auth = action.issue_auth();
        let object = action.action_mut().withdraw.withdraw(multisig, received, auth);
        transfer::public_transfer(object, action.action_mut().recipients.pop_back());
    }

    // step 5: destroy the action
    public fun complete_send(action: Action<Send>) {
        let Send { withdraw, recipients } = action.unpack_action();
        assert!(recipients.is_empty(), ESendAllAssetsBefore);
        withdraw.complete_withdraw();
    }

    // step 1: propose to deliver object to a recipient that must claim it
    public fun propose_delivery(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        objects: vector<ID>,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let withdraw = owned::new_withdraw(objects);
        let action = Deliver { withdraw, recipient };
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

    // step 4: creates a new delivery object that can only be shared (no store)
    public fun create_delivery(ctx: &mut TxContext): Delivery {
        Delivery { id: object::new(ctx), objects: bag::new(ctx) }
    }

    // step 5: loop over it in PTB, adds last object from the Deliver action
    public fun add_to_delivery<T: key + store>(
        delivery: &mut Delivery, 
        action: &mut Action<Deliver>, 
        multisig: &mut Multisig,
        received: Receiving<T>
    ) {
        let auth = action.issue_auth();
        let object = action.action_mut().withdraw.withdraw(multisig, received, auth);
        let index = delivery.objects.length();
        delivery.objects.add(index, object);
    }

    // step 6: share the Delivery and destroy the action
    #[allow(lint(share_owned))] // cannot be owned
    public fun deliver(delivery: Delivery, action: Action<Deliver>, ctx: &mut TxContext) {
        let Deliver { withdraw, recipient } = action.unpack_action();
        withdraw.complete_withdraw();
        
        transfer::transfer(
            DeliveryCap { id: object::new(ctx), delivery_id: object::id(&delivery) }, 
            recipient
        );
        transfer::share_object(delivery);
    }

    // step 7: loop over it in PTB, receiver claim objects
    public fun claim<T: key + store>(delivery: &mut Delivery, cap: &DeliveryCap): T {
        assert!(cap.delivery_id == object::id(delivery), EWrongDelivery);
        let index = delivery.objects.length() - 1;
        let object = delivery.objects.remove(index);
        object
    }

    // step 7 (bis): loop over it in PTB, multisig retrieve objects (member only)
    public fun retrieve<T: key + store>(
        delivery: &mut Delivery, 
        multisig: &Multisig,
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        let index = delivery.objects.length() - 1;
        let object: T = delivery.objects.remove(index);
        transfer::public_transfer(object, multisig.addr());
    }

    // step 8: destroy the delivery
    public fun complete_delivery(delivery: Delivery, cap: DeliveryCap) {
        let DeliveryCap { id, delivery_id: _ } = cap;
        id.delete();
        let Delivery { id, objects } = delivery;
        id.delete();
        assert!(objects.is_empty(), EDeliveryNotEmpty);
        objects.destroy_empty();
    }

    // step 8 (bis): destroy the delivery (member only)
    public fun cancel_delivery(
        multisig: &mut Multisig, 
        delivery: Delivery, 
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        let Delivery { id, objects } = delivery;
        id.delete();
        assert!(objects.is_empty(), EDeliveryNotEmpty);
        objects.destroy_empty();
    }
}


/// The user to transfer from / to must be a member of the multisig.
/// The functions take the caller's kiosk and the multisig's kiosk to execute the transfer.

module kraken::kiosk {
    use std::debug::print;
    use std::string::String;
    use sui::coin;
    use sui::transfer::Receiving;
    use sui::sui::SUI;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::transfer_policy::{TransferPolicy, TransferRequest};
    use kraken::multisig::{Multisig, Action};
    use kraken::owned::{Self, Borrow};

    // === Errors ===

    const EWrongReceiver: u64 = 1;
    const ETransferAllNftsBefore: u64 = 2;
    const EWrongNftsPrices: u64 = 3;

    // === Structs ===

    // action to be held in a proposal
    public struct Transfer has store {
        // request access to KioskOwnerCap
        borrow: Borrow,
        // id of the nfts to transfer
        nfts: vector<ID>,
        // owner of the receiver kiosk
        recipient: address,
    }

    // action to be held in a proposal
    public struct List has store {
        // request access to KioskOwnerCap
        borrow: Borrow,
        // id of the nfts to list
        nfts: vector<ID>,
        // sui amount
        prices: vector<u64>, 
    }

    // === Member only functions ===


    public fun new(multisig: &mut Multisig, ctx: &mut TxContext): (Kiosk, KioskOwnerCap) {
        multisig.assert_is_member(ctx);
        let (mut kiosk, cap) = kiosk::new(ctx);
        kiosk.set_owner_custom(&cap, multisig.addr());

        (kiosk, cap)
    }

    // === Multisig only functions ===

    // step 1: propose to transfer nfts to another kiosk
    public fun propose_transfer_to(
        multisig: &mut Multisig,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        cap_id: ID,
        nfts: vector<ID>,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let action = Transfer { 
            borrow: owned::new_borrow(vector[cap_id]), 
            nfts, 
            recipient 
        };

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

    // step 4: get multisig's KioskOwnerCap
    public fun borrow_cap_transfer(
        action: &mut Action<Transfer>,
        multisig: &mut Multisig, 
        multisig_cap: Receiving<KioskOwnerCap>,
    ): KioskOwnerCap {
        let auth = action.issue_auth();
        action.action_mut().borrow.borrow(multisig, multisig_cap, auth)
    }

    // step 4: move the nft and return the request for each nft in the action
    public fun transfer_to<T: key + store>(
        action: &mut Action<Transfer>,
        multisig_kiosk: &mut Kiosk, 
        multisig_cap: &KioskOwnerCap,
        receiver_kiosk: &mut Kiosk, 
        receiver_cap: &KioskOwnerCap, 
        ctx: &mut TxContext
    ): TransferRequest<T> {
        assert!(action.action_mut().recipient == ctx.sender(), EWrongReceiver);

        let nft_id = action.action_mut().nfts.pop_back();
        multisig_kiosk.list<T>(multisig_cap, nft_id, 0);
        let coin = coin::zero<SUI>(ctx);
        let (nft, request) = multisig_kiosk.purchase<T>(nft_id, coin);
        receiver_kiosk.place(receiver_cap, nft);

        request
    }

    // step 5: resolve the rules for the request

    // step 6: destroy the request (0x2::transfer_policy::confirm_request)

    // step 7: destroy the action and return the cap
    public fun complete_transfer_to(
        action: Action<Transfer>,
        multisig: &mut Multisig, 
        cap: KioskOwnerCap
    ) {
        let Transfer { mut borrow, nfts, recipient: _ } = action.unpack_action();
        borrow.put_back(multisig, cap);
        borrow.complete_borrow();
        assert!(nfts.is_empty(), ETransferAllNftsBefore);
        nfts.destroy_empty();
    }

    // step 1: propose to list nfts
    public fun propose_list(
        multisig: &mut Multisig,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        cap_id: ID,
        nfts: vector<ID>,
        prices: vector<u64>,
        ctx: &mut TxContext
    ) {
        assert!(nfts.length() == prices.length(), EWrongNftsPrices);
        let action = List { 
            borrow: owned::new_borrow(vector[cap_id]), 
            nfts, 
            prices 
        };
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

    // step 4: get multisig's KioskOwnerCap
    public fun borrow_cap_list(
        action: &mut Action<List>,
        multisig: &mut Multisig, 
        multisig_cap: Receiving<KioskOwnerCap>,
    ): KioskOwnerCap {
        let auth = action.issue_auth();
        action.action_mut().borrow.borrow(multisig, multisig_cap, auth)
    }

    // step 5: list last nft in action
    public fun list<T: key + store>(
        action: &mut Action<List>,
        kiosk: &mut Kiosk,
        cap: &KioskOwnerCap,
    ) {
        let nft_id = action.action_mut().nfts.pop_back();
        let price = action.action_mut().prices.pop_back();
        kiosk.list<T>(cap, nft_id, price);
    }
    
    // step 6: destroy the action and return the cap
    public fun complete_list(
        action: Action<List>, 
        multisig: &mut Multisig, 
        cap: KioskOwnerCap
    ) {
        let List { mut borrow, nfts, prices: _ } = action.unpack_action();
        borrow.put_back(multisig, cap);
        borrow.complete_borrow();
        assert!(nfts.is_empty(), ETransferAllNftsBefore);
        nfts.destroy_empty();
    }

    // // members can delist nfts
    // public fun delist<T: key + store>(
    //     multisig: &mut Multisig, 
    //     kiosk: &mut Kiosk, 
    //     cap: Receiving<KioskOwnerCap>,
    //     nft: ID,
    //     ctx: &mut TxContext
    // ) {
    //     multisig.assert_is_member(ctx);
    //     // access the multisig's KioskOwnerCap and use it to delist the nft
    //     let ms_cap_id = cap.receiving_object_id();
    //     let mut borrow = owned::new_borrow(vector[ms_cap_id]);
    //     let cap = borrow.borrow(multisig, cap, action.issuer());
    //     kiosk.delist<T>(&cap, nft);
    //     borrow.put_back(multisig, cap);
    //     borrow.complete_borrow();
    // }

    // members can withdraw the profits to the multisig
    public fun withdraw_profits(
        multisig: &mut Multisig,
        kiosk: &mut Kiosk,
        cap: &KioskOwnerCap,
        ctx: &mut TxContext
    ) {
        multisig.assert_is_member(ctx);
        let profits_mut = kiosk.profits_mut(cap);
        let profits_value = profits_mut.value();
        let profits = profits_mut.split(profits_value);

        transfer::public_transfer(
            coin::from_balance<SUI>(profits, ctx), 
            multisig.addr()
        );
    }

    // Test-only functions

    #[test_only]
    public fun place<T: key + store>(multisig_kiosk: &mut Kiosk, cap: &KioskOwnerCap, nft: T) {
        multisig_kiosk.place(cap, nft);
    }

    #[test_only]
    public fun kiosk_list<T: key + store>(multisig_kiosk: &mut Kiosk, cap: &KioskOwnerCap, nft_id: ID, price: u64)  {
        multisig_kiosk.list<T>(cap, nft_id, price);        
    }

    #[test_only]
    public fun borrow_cap(
        multisig: &mut Multisig, 
        multisig_cap: Receiving<KioskOwnerCap>,
    ): KioskOwnerCap {
        transfer::public_receive(multisig.uid_mut(), multisig_cap)
    }    
}


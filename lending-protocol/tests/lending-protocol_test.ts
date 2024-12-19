import {
    Chain,
    Account,
    Tx,
    types,
    assertEquals,
} from './deps.ts';

import { 
    Clarinet,
    Tx as ClarityTx,
    Block,
} from 'https://deno.land/x/clarinet@v1.5.4/index.ts';

Clarinet.test({
    name: "Ensures that protocol can be initialized with initial price",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;

        let block = chain.mineBlock([
            Tx.contractCall(
                'lending-protocol',
                'initialize-protocol',
                [types.uint(50000)],
                deployer.address
            )
        ]);
        assertEquals(block.receipts[0].result, '(ok true)');
    },
});

Clarinet.test({
    name: "Ensures users can provide collateral",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const wallet1 = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall(
                'lending-protocol',
                'provide-collateral',
                [types.uint(1000000)],
                wallet1.address
            )
        ]);
        assertEquals(block.receipts[0].result, '(ok true)');
        
        // Verify position
        const position = chain.callReadOnlyFn(
            'lending-protocol',
            'get-user-position',
            [types.principal(wallet1.address)],
            wallet1.address
        );
        
        assertEquals(
            position.result,
            `(some {total-borrowed: u0, total-collateral: u1000000, loan-count: u0})`
        );
    },
});

Clarinet.test({
    name: "Ensures users can take loans with sufficient collateral",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;
        
        // Initialize protocol
        chain.mineBlock([
            Tx.contractCall(
                'lending-protocol',
                'initialize-protocol',
                [types.uint(50000)],
                deployer.address
            )
        ]);
        
        // Provide collateral
        chain.mineBlock([
            Tx.contractCall(
                'lending-protocol',
                'provide-collateral',
                [types.uint(1000000)],
                wallet1.address
            )
        ]);
        
        // Take loan
        let block = chain.mineBlock([
            Tx.contractCall(
                'lending-protocol',
                'take-loan',
                [types.uint(500000)],
                wallet1.address
            )
        ]);
        
        assertEquals(block.receipts[0].result, '(ok true)');
        
        // Verify loan data
        const loan = chain.callReadOnlyFn(
            'lending-protocol',
            'get-loan-data',
            [types.principal(wallet1.address)],
            wallet1.address
        );
        
        // Verify loan exists and is active
        assertEquals(loan.result.includes('"active"'), true);
    },
});

Clarinet.test({
    name: "Ensures loans can be repaid",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const wallet1 = accounts.get('wallet_1')!;
        
        // Setup: Initialize, provide collateral, take loan
        chain.mineBlock([
            Tx.contractCall(
                'lending-protocol',
                'initialize-protocol',
                [types.uint(50000)],
                deployer.address
            ),
            Tx.contractCall(
                'lending-protocol',
                'provide-collateral',
                [types.uint(1000000)],
                wallet1.address
            ),
            Tx.contractCall(
                'lending-protocol',
                'take-loan',
                [types.uint(500000)],
                wallet1.address
            )
        ]);
        
        // Repay loan
        let block = chain.mineBlock([
            Tx.contractCall(
                'lending-protocol',
                'repay-loan',
                [types.uint(500000)],
                wallet1.address
            )
        ]);
        
        assertEquals(block.receipts[0].result, '(ok true)');
        
        // Verify loan is closed
        const loan = chain.callReadOnlyFn(
            'lending-protocol',
            'get-loan-data',
            [types.principal(wallet1.address)],
            wallet1.address
        );
        
        assertEquals(loan.result, 'none');
    },
});

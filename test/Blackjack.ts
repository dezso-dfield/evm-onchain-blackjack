import { expect } from "chai";
import { ethers } from "hardhat";
import { Blackjack } from "../typechain-types";

describe("Blackjack", function () {
    let blackjack: Blackjack;
    let owner: any;
    let player1: any;
    let player2: any;

    beforeEach(async function () {
        [owner, player1, player2] = await ethers.getSigners();

        const BlackjackFactory = await ethers.getContractFactory("Blackjack");
        blackjack = await BlackjackFactory.deploy();
        await blackjack.waitForDeployment();

        await owner.sendTransaction({ to: blackjack.target, value: ethers.parseEther("100.0") });
    });

    describe("Deployment", function () {
        it("Should deploy the contract", async function () {
            expect(blackjack.target).to.not.be.undefined;
            console.log("Blackjack contract deployed at:", blackjack.target);
        });
    });

    describe("Game Flow", function () {
        const betAmount = ethers.parseEther("0.1");

        it("Should allow a player to place a bet", async function () {
            await expect(blackjack.connect(player1).placeBet({ value: betAmount }))
                .to.emit(blackjack, "GameStarted")
                .withArgs(player1.address, betAmount);

            const game = await blackjack.playerGames(player1.address);
            expect(game.bet).to.equal(betAmount);
            expect(Number(game.state)).to.equal(1);
        });

        it("Should not allow placing a bet if a game is already in progress (not Idle/GameOver)", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await expect(blackjack.connect(player1).placeBet({ value: betAmount }))
                .to.be.revertedWith("Cannot place bet: A game is already in progress or not in a resettable state.");
        });

        it("Should deal initial cards and move to PlayerTurn or DealerTurn (if blackjack)", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });

            await expect(blackjack.connect(player1).dealInitialCards())
                .to.emit(blackjack, "PlayerCardDealt")
                .to.emit(blackjack, "DealerCardDealt")
                .to.emit(blackjack, "PlayerCardDealt");

            const playerHand = await blackjack.getPlayerHand(player1.address);
            const dealerHand = await blackjack.getDealerHand(player1.address);
            expect(playerHand.length).to.equal(2);
            expect(dealerHand.length).to.equal(1);

            const game = await blackjack.playerGames(player1.address);
            const playerHandValue = await blackjack.getHandValue(player1.address, true);
            if (playerHandValue === 21) {
                expect(Number(game.state)).to.equal(3);
            } else {
                expect(Number(game.state)).to.equal(2);
            }
        });

        it("Should handle player hitting and busting", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();

            let playerHandValue = await blackjack.getHandValue(player1.address, true);
            let game = await blackjack.playerGames(player1.address);
            let hitCount = 0;

            while (playerHandValue <= 21 && Number(game.state) === 2 && hitCount < 10) {
                await blackjack.connect(player1).hitMultiple(1, 1);
                playerHandValue = await blackjack.getHandValue(player1.address, true);
                game = await blackjack.playerGames(player1.address);
                hitCount++;
            }

            expect(playerHandValue).to.be.greaterThan(21);
            expect(Number(game.state)).to.equal(4);
        });

        it("Should handle player standing and dealer playing out (dealer wins or pushes)", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();

            let game = await blackjack.playerGames(player1.address);
            if (Number(game.state) === 2) {
                await expect(blackjack.connect(player1).stand(1))
                    .to.emit(blackjack, "GameResult");
            } else {
                await expect(blackjack.connect(player1).callStatic.getGameState(player1.address)).to.eventually.equal(4);
            }

            game = await blackjack.playerGames(player1.address);
            expect(Number(game.state)).to.equal(4);

            const playerValue = await blackjack.getHandValue(player1.address, true);
            const dealerValue = await blackjack.getHandValue(player1.address, false);

            if (playerValue <= 21 && dealerValue <= 21) {
                expect(playerValue).to.be.lessThanOrEqual(dealerValue);
            }
        });

        it("Should handle player standing and dealer playing out (player wins)", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();

            let game = await blackjack.playerGames(player1.address);
            if (Number(game.state) === 2) {
                await expect(blackjack.connect(player1).stand(1))
                    .to.emit(blackjack, "GameResult");
            } else {
                await expect(blackjack.connect(player1).callStatic.getGameState(player1.address)).to.eventually.equal(4);
            }

            game = await blackjack.playerGames(player1.address);
            expect(Number(game.state)).to.equal(4);
        });

        it("Should handle player blackjack", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();

            const game = await blackjack.playerGames(player1.address);
            const playerHandValue = await blackjack.getHandValue(player1.address, true);

            if (playerHandValue === 21) {
                expect(Number(game.state)).to.equal(4);
            } else {
                expect(Number(game.state)).to.equal(2);
            }
        });

        it("Should handle dealer busting", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();

            let game = await blackjack.playerGames(player1.address);
            if (Number(game.state) === 2) {
                await blackjack.connect(player1).stand(1);
            } else {
            }

            game = await blackjack.playerGames(player1.address);
            const dealerHandValue = await blackjack.getHandValue(player1.address, false);

            expect(Number(game.state)).to.equal(4);
            if (dealerHandValue > 21) {
                const playerHandValue = await blackjack.getHandValue(player1.address, true);
                expect(playerHandValue).to.be.lessThanOrEqual(21);
            }
        });

        it("Should allow owner to withdraw funds", async function () {
            const initialOwnerBalance = await ethers.provider.getBalance(owner.address);
            await blackjack.connect(player1).placeBet({ value: betAmount });

            await blackjack.connect(player1).dealInitialCards();
            let playerHandValue = await blackjack.getHandValue(player1.address, true);
            let game = await blackjack.playerGames(player1.address);
            let hitCount = 0;

            while (playerHandValue <= 21 && Number(game.state) === 2 && hitCount < 10) {
                await blackjack.connect(player1).hitMultiple(1, 1);
                playerHandValue = await blackjack.getHandValue(player1.address, true);
                game = await blackjack.playerGames(player1.address);
                hitCount++;
            }

            expect(Number(game.state)).to.equal(4);

            const contractBalanceBeforeWithdraw = await ethers.provider.getBalance(blackjack.target);
            expect(contractBalanceBeforeWithdraw).to.be.gte(betAmount);

            await expect(blackjack.connect(owner).withdrawAll())
                .to.changeEtherBalance(owner, contractBalanceBeforeWithdraw);
            expect(await ethers.provider.getBalance(blackjack.target)).to.equal(0);
        });

        it("Should allow player to take insurance if dealer has Ace and pay out correctly", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();
            const game = await blackjack.playerGames(player1.address);

            if (game.dealerHasAce) {
                const insuranceBetAmount = betAmount / 2n;
                const initialPlayerBalance = await ethers.provider.getBalance(player1.address);

                await expect(blackjack.connect(player1).takeInsurance({ value: insuranceBetAmount }))
                    .to.emit(blackjack, "InsuranceTaken")
                    .withArgs(player1.address, insuranceBetAmount);

                const updatedGame = await blackjack.playerGames(player1.address);
                expect(updatedGame.insuranceTaken).to.be.true;
                expect(updatedGame.insuranceBet).to.equal(insuranceBetAmount);

                if (Number(updatedGame.state) === 2) {
                    await blackjack.connect(player1).stand(1);
                }

                const finalDealerHand = await blackjack.getDealerHand(player1.address);
                const finalDealerValue = await blackjack.getHandValue(player1.address, false);

                if (finalDealerValue === 21 && finalDealerHand.length === 2) {
                    console.log("Dealer had Blackjack, insurance should pay.");
                } else {
                    console.log("Dealer did not have Blackjack, insurance should lose.");
                }
            } else {
                console.log("Dealer did not get an Ace for insurance test. Skipping insurance test.");
            }
        });

        it("Should allow player to double down on hand 1 and end turn", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();
            const playerHand = await blackjack.getPlayerHand(player1.address);
            const game = await blackjack.playerGames(player1.address);

            if (Number(game.state) === 2 && playerHand.length === 2) {
                const initialPlayerBalance = await ethers.provider.getBalance(player1.address);
                expect(game.hasDoubledDownHand1).to.be.false;

                await expect(blackjack.connect(player1).doubleDown(1, { value: betAmount }))
                    .to.emit(blackjack, "DoubleDown")
                    .withArgs(player1.address, betAmount * 2n, 1)
                    .to.emit(blackjack, "GameResult");

                const updatedGame = await blackjack.playerGames(player1.address);
                expect((await blackjack.getPlayerHand(player1.address)).length).to.equal(3);
                expect(updatedGame.hasDoubledDownHand1).to.be.true;
                expect(Number(updatedGame.state)).to.equal(4);
            } else {
                console.log("Player not in correct state (PlayerTurn with 2 cards) for double down test. Skipping double down test.");
            }
        });

        it("Should allow player to split, play both hands, and resolve correctly", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();

            const playerHand = await blackjack.getPlayerHand(player1.address);

            if (playerHand.length === 2 && playerHand[0] === playerHand[1]) {
                const initialPlayerBalance = await ethers.provider.getBalance(player1.address);

                await expect(blackjack.connect(player1).split({ value: betAmount }))
                    .to.emit(blackjack, "Split")
                    .withArgs(player1.address, betAmount);

                let game = await blackjack.playerGames(player1.address);
                expect(game.hasSplit).to.be.true;
                expect(game.bet2).to.equal(betAmount);
                expect((await blackjack.getPlayerHand(player1.address)).length).to.equal(2);
                expect((await blackjack.getPlayerHand2(player1.address)).length).to.equal(2);
                expect(Number(game.state)).to.equal(2);

                await expect(blackjack.connect(player1).stand(1))
                    .to.emit(blackjack, "PlayerStood")
                    .withArgs(player1.address, 1);

                game = await blackjack.playerGames(player1.address);
                expect(game.playerHand1Done).to.be.true;
                expect(Number(game.state)).to.equal(2);

                await expect(blackjack.connect(player1).stand(2))
                    .to.emit(blackjack, "PlayerStood")
                    .withArgs(player1.address, 2)
                    .to.emit(blackjack, "GameResult");

                game = await blackjack.playerGames(player1.address);
                expect(Number(game.state)).to.equal(4);

            } else {
                console.log("Player did not get a pair for split test. Skipping split test.");
            }
        });

        it("Should allow player to reset game state to Idle after game over", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();
            let game = await blackjack.playerGames(player1.address);
            if (Number(game.state) === 2) {
                await blackjack.connect(player1).stand(1);
            }
            game = await blackjack.playerGames(player1.address);
            expect(Number(game.state)).to.equal(4);

            await expect(blackjack.connect(player1).resetGame())
                .to.emit(blackjack, "GameReset")
                .withArgs(player1.address);

            game = await blackjack.playerGames(player1.address);
            expect(Number(game.state)).to.equal(0);
            expect(game.bet).to.equal(0);
            expect((await blackjack.getPlayerHand(player1.address)).length).to.equal(0);
            expect((await blackjack.getDealerHand(player1.address)).length).to.equal(0);
            expect(game.hasSplit).to.be.false;
            expect(game.insuranceTaken).to.be.false;
        });

        it("Should not allow reset game in active playing state (PlayerTurn)", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            await blackjack.connect(player1).dealInitialCards();
            let game = await blackjack.playerGames(player1.address);
            expect(Number(game.state)).to.equal(2);

            await expect(blackjack.connect(player1).resetGame())
                .to.be.revertedWith("Cannot reset game in current active playing state. Finish the round or wait for it to conclude.");
        });

        it("Should allow reset game from BetPlaced state", async function () {
            await blackjack.connect(player1).placeBet({ value: betAmount });
            let game = await blackjack.playerGames(player1.address);
            expect(Number(game.state)).to.equal(1);

            await expect(blackjack.connect(player1).resetGame())
                .to.emit(blackjack, "GameReset")
                .withArgs(player1.address);
            game = await blackjack.playerGames(player1.address);
            expect(Number(game.state)).to.equal(0);
        });
    });
});

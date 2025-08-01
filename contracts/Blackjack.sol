// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Blackjack {
    enum GameState {
        Idle,         // 0 - No game in progress, ready to place a bet
        BetPlaced,    // 1 - Bet placed, waiting for initial cards to be dealt
        PlayerTurn,   // 2 - Player can hit, stand, double down, or split
        DealerTurn,   // 3 - Dealer plays out their hand
        GameOver      // 4 - Game has concluded, results determined, ready for reset or new game
    }

    struct PlayerGame {
        uint256 bet; // Main hand bet
        uint8[] playerHand;
        uint8[] dealerHand;
        GameState state;
        uint256 lastBlockNumber;
        bool playerStood; // Used for single hand, or if only one hand for split is done

        uint256 bet2; // Second hand bet (for split)
        uint8[] playerHand2; // Second hand (for split)
        bool hasSplit;
        bool playerHand1Done; // True if player has finished playing hand 1 after a split
        bool hasDoubledDownHand1; // True if player doubled down on hand 1
        bool hasDoubledDownHand2; // True if player doubled down on hand 2
        uint256 insuranceBet; // Insurance side bet
        bool insuranceTaken; // Flag if insurance was taken
        bool dealerHasAce; // Flag if dealer's up card is an Ace
    }

    mapping(address => PlayerGame) public playerGames;
    address public owner; // Added public owner variable

    event GameStarted(address indexed player, uint256 betAmount);
    event PlayerCardDealt(address indexed player, uint8 card, uint256 handValue, uint8 handId);
    event DealerCardDealt(address indexed player, uint8 card, uint256 handValue);
    event PlayerStood(address indexed player, uint8 handId);
    event PlayerBust(address indexed player, uint256 finalHandValue, uint8 handId);
    event DealerBust(address indexed player, uint256 finalHandValue);
    event GameResult(address indexed player, string result, uint256 winnings);
    event InsuranceTaken(address indexed player, uint256 amount);
    event DoubleDown(address indexed player, uint256 newBet, uint8 handId);
    event Split(address indexed player, uint256 betAmount);
    event GameReset(address indexed player);

    modifier inState(GameState _state) {
        require(playerGames[msg.sender].state == _state, "Invalid game state for this action.");
        _;
    }

    // This modifier is not directly used in the current version but is good to keep
    modifier notInState(GameState _state) {
        require(playerGames[msg.sender].state != _state, "Invalid game state for this action.");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    constructor() {
        owner = msg.sender; // Set the deployer as the owner
    }

    receive() external payable {}

    function placeBet() external payable {
        // Consolidated state check for placing a new bet
        require(
            playerGames[msg.sender].state == GameState.Idle ||
            playerGames[msg.sender].state == GameState.GameOver,
            "Cannot place bet: A game is already in progress or not in a resettable state."
        );
        require(msg.value > 0, "Bet amount must be greater than zero.");

        PlayerGame storage game = playerGames[msg.sender];

        game.bet = msg.value;
        game.playerHand = new uint8[](0);
        game.dealerHand = new uint8[](0);
        game.state = GameState.BetPlaced;
        game.playerStood = false;
        game.lastBlockNumber = block.number; // Initialize for randomness

        // Reset all split/double down/insurance specific fields for a new game
        game.bet2 = 0;
        game.playerHand2 = new uint8[](0);
        game.hasSplit = false;
        game.playerHand1Done = false;
        game.hasDoubledDownHand1 = false;
        game.hasDoubledDownHand2 = false;
        game.insuranceBet = 0;
        game.insuranceTaken = false;
        game.dealerHasAce = false;

        emit GameStarted(msg.sender, msg.value);
    }

    function dealInitialCards() external inState(GameState.BetPlaced) {
        PlayerGame storage game = playerGames[msg.sender];

        _dealCard(msg.sender, true, 1); // Player card 1 (hand 1)
        uint8 dealerUpCard = _dealCard(msg.sender, false, 0); // Dealer up card (hand 0)
        _dealCard(msg.sender, true, 1); // Player card 2 (hand 1)

        if (dealerUpCard == 1) { // Ace
            game.dealerHasAce = true;
        }

        uint256 playerValue = _calculateHandValue(game.playerHand);
        if (playerValue == 21) {
            // Player has Blackjack, move to DealerTurn to check for dealer's possible Blackjack
            game.state = GameState.DealerTurn;
            _dealerPlay(msg.sender); // Dealer plays out
        } else {
            game.state = GameState.PlayerTurn;
        }
    }

    function hitMultiple(uint8 _numHits, uint8 _handId) external inState(GameState.PlayerTurn) {
        PlayerGame storage game = playerGames[msg.sender];
        require(_numHits > 0, "Must hit at least one card.");

        uint8[] storage currentHand;
        bool hasDoubledDownFlag;
        if (_handId == 1) {
            require(!game.playerHand1Done, "Hand 1 is already done.");
            currentHand = game.playerHand;
            hasDoubledDownFlag = game.hasDoubledDownHand1;
        } else if (_handId == 2 && game.hasSplit) {
            require(game.playerHand1Done, "Hand 1 must be done before playing Hand 2.");
            currentHand = game.playerHand2;
            hasDoubledDownFlag = game.hasDoubledDownHand2;
        } else {
            revert("Invalid hand ID or no split hand to hit.");
        }
        require(!hasDoubledDownFlag, "Cannot hit after doubling down on this hand.");

        for (uint8 i = 0; i < _numHits; i++) {
            _dealCard(msg.sender, true, _handId);
            uint256 playerValue = _calculateHandValue(currentHand);

            if (playerValue > 21) {
                emit PlayerBust(msg.sender, playerValue, _handId);
                if (game.hasSplit) {
                    if (_handId == 1) {
                        game.playerHand1Done = true;
                        // If hand 1 busts, and hand 2 is active, player continues with hand 2
                        if (!game.hasDoubledDownHand2 && _calculateHandValue(game.playerHand2) > 0) {
                            // Remain in PlayerTurn for hand 2
                        } else {
                            game.state = GameState.DealerTurn;
                            _dealerPlay(msg.sender);
                        }
                    } else { // Hand 2 busts
                        game.state = GameState.DealerTurn;
                        _dealerPlay(msg.sender);
                    }
                } else {
                    _endGame(msg.sender, "Player Busts", 0); // No split, direct game end
                }
                return; // Exit after bust
            } else if (playerValue == 21) {
                // Player got 21, automatically stands on this hand
                emit PlayerStood(msg.sender, _handId);
                if (game.hasSplit) {
                    if (_handId == 1) {
                        game.playerHand1Done = true;
                        // If hand 1 gets 21, and hand 2 is active, player continues with hand 2
                        if (!game.hasDoubledDownHand2 && _calculateHandValue(game.playerHand2) > 0) {
                            // Remain in PlayerTurn for hand 2
                        } else {
                            game.state = GameState.DealerTurn;
                            _dealerPlay(msg.sender);
                        }
                    } else { // Hand 2 got 21
                        game.state = GameState.DealerTurn;
                        _dealerPlay(msg.sender);
                    }
                } else {
                    game.state = GameState.DealerTurn;
                    _dealerPlay(msg.sender);
                }
                return; // Exit after 21
            }
        }
    }

    function stand(uint8 _handId) external inState(GameState.PlayerTurn) {
        PlayerGame storage game = playerGames[msg.sender];

        if (_handId == 1) {
            require(!game.playerHand1Done, "Hand 1 is already done.");
            require(!game.hasDoubledDownHand1, "Cannot stand on hand 1 after doubling down.");
            game.playerHand1Done = true;
            emit PlayerStood(msg.sender, 1);
            if (game.hasSplit && _calculateHandValue(game.playerHand2) > 0 && !game.hasDoubledDownHand2) {
                // If split, and hand 2 is active and not doubled down, remain in PlayerTurn for hand 2
            } else {
                game.state = GameState.DealerTurn;
                _dealerPlay(msg.sender);
            }
        } else if (_handId == 2 && game.hasSplit) {
            require(game.playerHand1Done, "Hand 1 must be done before playing Hand 2.");
            require(!game.hasDoubledDownHand2, "Cannot stand on hand 2 after doubling down.");
            emit PlayerStood(msg.sender, 2);
            game.state = GameState.DealerTurn;
            _dealerPlay(msg.sender);
        } else {
            revert("Invalid hand ID or no split hand to stand on.");
        }
    }

    function doubleDown(uint8 _handId) external payable inState(GameState.PlayerTurn) {
        PlayerGame storage game = playerGames[msg.sender];

        uint8[] storage currentHand;
        if (_handId == 1) {
            require(!game.playerHand1Done, "Hand 1 is already done.");
            require(!game.hasDoubledDownHand1, "Already doubled down on hand 1.");
            require(game.playerHand.length == 2, "Can only double down on initial two cards.");
            require(msg.value == game.bet, "Must double the original bet for hand 1.");
            game.bet += msg.value;
            game.hasDoubledDownHand1 = true;
            currentHand = game.playerHand;
        } else if (_handId == 2 && game.hasSplit) {
            require(game.playerHand1Done, "Hand 1 must be done before playing Hand 2.");
            require(!game.hasDoubledDownHand2, "Already doubled down on hand 2.");
            require(game.playerHand2.length == 2, "Can only double down on initial two cards for split hand.");
            require(msg.value == game.bet2, "Must double the original bet for hand 2.");
            game.bet2 += msg.value;
            game.hasDoubledDownHand2 = true;
            currentHand = game.playerHand2;
        } else {
            revert("Invalid hand ID or no split hand to double down on.");
        }

        _dealCard(msg.sender, true, _handId); // Deal one more card after doubling down
        emit DoubleDown(msg.sender, _handId == 1 ? game.bet : game.bet2, _handId);

        uint256 playerValue = _calculateHandValue(currentHand);
        if (playerValue > 21) {
            emit PlayerBust(msg.sender, playerValue, _handId);
            if (game.hasSplit) {
                if (_handId == 1) {
                    game.playerHand1Done = true;
                    if (!game.hasDoubledDownHand2 && _calculateHandValue(game.playerHand2) > 0) {
                        // Remain in PlayerTurn for hand 2
                    } else {
                        game.state = GameState.DealerTurn;
                        _dealerPlay(msg.sender);
                    }
                } else { // Hand 2 busted after double down
                    game.state = GameState.DealerTurn;
                    _dealerPlay(msg.sender);
                }
            } else {
                _endGame(msg.sender, "Player Busts (Double Down)", 0);
            }
        } else {
            emit PlayerStood(msg.sender, _handId); // Player automatically stands after double down
            if (game.hasSplit) {
                if (_handId == 1) {
                    game.playerHand1Done = true;
                    if (!game.hasDoubledDownHand2 && _calculateHandValue(game.playerHand2) > 0) {
                        // Remain in PlayerTurn for hand 2
                    } else {
                        game.state = GameState.DealerTurn;
                        _dealerPlay(msg.sender);
                    }
                } else { // Hand 2 done after double down
                    game.state = GameState.DealerTurn;
                    _dealerPlay(msg.sender);
                }
            } else {
                game.state = GameState.DealerTurn;
                _dealerPlay(msg.sender);
            }
        }
    }

    function split() external payable inState(GameState.PlayerTurn) {
        PlayerGame storage game = playerGames[msg.sender];
        require(!game.hasSplit, "Player has already split.");
        require(game.playerHand.length == 2, "Can only split initial two cards.");
        require(game.playerHand[0] == game.playerHand[1], "Cards must be of the same rank to split.");
        require(msg.value == game.bet, "Must place an equal bet for the second hand.");

        game.hasSplit = true;
        game.bet2 = msg.value;

        // Move one card from playerHand to playerHand2
        game.playerHand2.push(game.playerHand[1]);
        game.playerHand.pop(); // Remove the last card from playerHand (which was moved)

        // Deal one new card to each hand
        _dealCard(msg.sender, true, 1);
        _dealCard(msg.sender, true, 2);

        // If either hand immediately gets 21, it stands automatically
        uint256 hand1Value = _calculateHandValue(game.playerHand);
        uint256 hand2Value = _calculateHandValue(game.playerHand2);

        if (hand1Value == 21) {
            game.playerHand1Done = true;
            emit PlayerStood(msg.sender, 1);
        }
        if (hand2Value == 21) {
            // Hand 2 getting 21 means player finishes both hands if hand 1 also done, or proceeds to hand 1 if not.
            // This flag is mainly to indicate readiness for dealer turn.
            if (hand1Value == 21) { // If both get 21
                game.playerHand1Done = true; // Ensure both are considered done
            }
            emit PlayerStood(msg.sender, 2);
        }

        // If both hands are 21 from split, then go to dealer turn.
        if (hand1Value == 21 && hand2Value == 21) {
            game.state = GameState.DealerTurn;
            _dealerPlay(msg.sender);
        }
        // Otherwise, remain in PlayerTurn to allow playing hand 1.

        emit Split(msg.sender, game.bet);
    }

    function takeInsurance() external payable inState(GameState.PlayerTurn) {
        PlayerGame storage game = playerGames[msg.sender];
        require(game.dealerHasAce, "Insurance can only be taken if dealer shows an Ace.");
        require(!game.insuranceTaken, "Insurance already taken.");
        require(msg.value == game.bet / 2, "Insurance bet must be half of the original bet.");

        game.insuranceBet = msg.value;
        game.insuranceTaken = true;
        emit InsuranceTaken(msg.sender, msg.value);
    }

    /**
     * @dev Resets the player's game state to Idle.
     * Can be called if the game is stuck or to start over.
     */
    function resetGame() external {
        PlayerGame storage game = playerGames[msg.sender];
        // Only allow resetting if not in an active playing state that needs resolution
        // Allow Idle, GameOver, and BetPlaced.
        require(
            game.state == GameState.Idle ||
            game.state == GameState.GameOver ||
            game.state == GameState.BetPlaced,
            "Cannot reset game in current active playing state. Finish the round or wait for it to conclude."
        );

        // Clear all game-related state variables
        game.bet = 0;
        game.playerHand = new uint8[](0);
        game.dealerHand = new uint8[](0);
        game.state = GameState.Idle;
        game.playerStood = false; // Reset for single hand logic
        game.lastBlockNumber = 0; // Reset last block number for randomness seed

        game.bet2 = 0;
        game.playerHand2 = new uint8[](0);
        game.hasSplit = false;
        game.playerHand1Done = false;
        game.hasDoubledDownHand1 = false;
        game.hasDoubledDownHand2 = false;
        game.insuranceBet = 0;
        game.insuranceTaken = false;
        game.dealerHasAce = false;

        emit GameReset(msg.sender);
    }

    function getHandValue(address _player, bool _isPlayerHand) public view returns (uint256) {
        if (_isPlayerHand) {
            return _calculateHandValue(playerGames[_player].playerHand);
        } else {
            return _calculateHandValue(playerGames[_player].dealerHand);
        }
    }

    function getHandValue2(address _player) public view returns (uint256) {
        return _calculateHandValue(playerGames[_player].playerHand2);
    }

    function getGameState(address _player) public view returns (GameState) {
        return playerGames[_player].state;
    }

    function getPlayerHand(address _player) public view returns (uint8[] memory) {
        return playerGames[_player].playerHand;
    }

    function getPlayerHand2(address _player) public view returns (uint8[] memory) {
        return playerGames[_player].playerHand2;
    }

    function getDealerHand(address _player) public view returns (uint8[] memory) {
        return playerGames[_player].dealerHand;
    }

    function _dealCard(address _player, bool _toPlayer, uint8 _handId) internal returns (uint8) {
        PlayerGame storage game = playerGames[_player];

        // Using block.prevrandao is deprecated and insecure for production.
        // For testing and simple demonstrations, it's acceptable.
        // For production, consider Chainlink VRF or similar.
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, _player, game.lastBlockNumber)));
        game.lastBlockNumber = block.number; // Update for next randomness calculation

        uint8 card = uint8((randomNumber % 13) + 1); // 1-13
        if (card > 10) { // J, Q, K become 10
            card = 10;
        }

        if (_toPlayer) {
            if (_handId == 1) {
                game.playerHand.push(card);
                emit PlayerCardDealt(_player, card, _calculateHandValue(game.playerHand), 1);
            } else if (_handId == 2) {
                game.playerHand2.push(card);
                emit PlayerCardDealt(_player, card, _calculateHandValue(game.playerHand2), 2);
            } else {
                revert("Invalid player hand ID for dealing.");
            }
        } else { // Deal to dealer
            game.dealerHand.push(card);
            emit DealerCardDealt(_player, card, _calculateHandValue(game.dealerHand));
        }
        return card;
    }

    function _calculateHandValue(uint8[] memory _hand) internal pure returns (uint256) {
        uint256 value = 0;
        uint256 numAces = 0;

        for (uint i = 0; i < _hand.length; i++) {
            if (_hand[i] == 1) { // Ace
                numAces++;
                value += 11;
            } else {
                value += _hand[i];
            }
        }

        // Adjust for Aces if busted
        while (value > 21 && numAces > 0) {
            value -= 10; // Change Ace from 11 to 1
            numAces--;
        }
        return value;
    }

    function _dealerPlay(address _player) internal {
        PlayerGame storage game = playerGames[_player];
        uint256 dealerValue = _calculateHandValue(game.dealerHand);

        // Dealer reveals their second card (if only one was dealt initially)
        if (game.dealerHand.length == 1) {
             _dealCard(_player, false, 0); // Corrected: Use _player for the player's game state
             dealerValue = _calculateHandValue(game.dealerHand);
        }

        // Handle insurance payout
        if (game.insuranceTaken) {
            if (dealerValue == 21 && game.dealerHand.length == 2) { // Dealer has Blackjack
                (bool success, ) = payable(_player).call{value: game.insuranceBet * 3}("");
                require(success, "Failed to send insurance winnings.");
            } else {
                // Insurance lost, no payout
            }
        }

        // Dealer hits until hand value is 17 or more
        while (dealerValue < 17) {
            _dealCard(_player, false, 0); // Corrected: Use _player for the player's game state
            dealerValue = _calculateHandValue(game.dealerHand);
        }

        if (dealerValue > 21) {
            emit DealerBust(_player, dealerValue);
            _resolveGameOutcome(_player, true); // Dealer busted
        } else {
            _resolveGameOutcome(_player, false); // Dealer did not bust
        }
    }

    function _resolveGameOutcome(address _player, bool _dealerBusted) internal {
        PlayerGame storage game = playerGames[_player];
        uint256 dealerValue = _calculateHandValue(game.dealerHand);

        // Resolve outcome for the primary hand
        _determineHandOutcome(_player, game.playerHand, game.bet, 1, dealerValue, _dealerBusted);

        // If split, resolve outcome for the second hand
        if (game.hasSplit) {
            _determineHandOutcome(_player, game.playerHand2, game.bet2, 2, dealerValue, _dealerBusted);
        }

        game.state = GameState.GameOver; // Set game state to Game Over
    }

    function _determineHandOutcome(
        address _player,
        uint8[] memory _hand,
        uint256 _bet,
        uint8 _handId,
        uint256 _dealerValue,
        bool _dealerBusted
    ) internal {
        uint256 playerValue = _calculateHandValue(_hand);
        string memory result;
        uint256 winnings = 0;

        if (playerValue > 21) {
            result = string.concat("Hand ", _uint8ToString(_handId), ": Player Busts");
            winnings = 0; // Player busts, loses bet
        } else if (_dealerBusted) {
            result = string.concat("Hand ", _uint8ToString(_handId), ": Dealer Busts! You Win!");
            winnings = _bet * 2; // Player wins 2x bet (return bet + 1x winnings)
        } else if (playerValue > _dealerValue) {
            result = string.concat("Hand ", _uint8ToString(_handId), ": You Win!");
            winnings = _bet * 2; // Player wins 2x bet
        } else if (playerValue < _dealerValue) {
            result = string.concat("Hand ", _uint8ToString(_handId), ": Dealer Wins");
            winnings = 0; // Player loses bet
        } else { // Push
            result = string.concat("Hand ", _uint8ToString(_handId), ": Push (It's a Tie)");
            winnings = _bet; // Player gets bet back
        }

        if (winnings > 0) {
            (bool success, ) = payable(_player).call{value: winnings}("");
            require(success, string.concat("Failed to send Ether for Hand ", _uint8ToString(_handId)));
        }
        emit GameResult(_player, result, winnings);
    }

    // Helper function to convert uint8 to string for event messages
    function _uint8ToString(uint8 _val) internal pure returns (string memory) {
        if (_val == 0) {
            return "0";
        }
        uint256 value = _val;
        uint256 length = 0;
        uint256 temp = value;
        while (temp > 0) {
            temp /= 10;
            length++;
        }

        bytes memory buffer = new bytes(length);
        uint256 i = length;
        while (value > 0) {
            i--;
            buffer[i] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // This _endGame function is primarily for non-split scenarios where player busts immediately.
    // In other cases, _resolveGameOutcome is called.
    function _endGame(address _player, string memory _result, uint256 _winnings) internal {
        PlayerGame storage game = playerGames[_player];
        game.state = GameState.GameOver;
        if (_winnings > 0) {
            (bool success, ) = payable(_player).call{value: _winnings}("");
            require(success, "Failed to send Ether.");
        }
        emit GameResult(_player, _result, _winnings);
    }

    function withdrawAll() external onlyOwner { // Applied onlyOwner modifier
        payable(msg.sender).transfer(address(this).balance);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Blackjack {
    enum GameState {
        Idle,
        BetPlaced,
        PlayerTurn,
        DealerTurn,
        GameOver
    }

    struct PlayerGame {
        uint256 bet; // Main hand bet
        uint8[] playerHand;
        uint8[] dealerHand;
        GameState state;
        uint256 lastBlockNumber;
        bool playerStood;

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
    event GameReset(address indexed player); // New event for game reset

    modifier inState(GameState _state) {
        require(playerGames[msg.sender].state == _state, "Invalid game state for this action.");
        _;
    }

    modifier notInState(GameState _state) {
        require(playerGames[msg.sender].state != _state, "Invalid game state for this action.");
        _;
    }

    constructor() {}

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
        game.lastBlockNumber = block.number;

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

        _dealCard(msg.sender, true, 1);
        uint8 dealerUpCard = _dealCard(msg.sender, false, 0);
        _dealCard(msg.sender, true, 1);

        if (dealerUpCard == 1) {
            game.dealerHasAce = true;
        }

        uint256 playerValue = _calculateHandValue(game.playerHand);
        if (playerValue == 21) {
            game.state = GameState.DealerTurn;
            _dealerPlay(msg.sender);
        } else {
            game.state = GameState.PlayerTurn;
        }
    }

    function hitMultiple(uint8 _numHits, uint8 _handId) external inState(GameState.PlayerTurn) {
        PlayerGame storage game = playerGames[msg.sender];
        require(_numHits > 0, "Must hit at least one card.");
        require(!game.hasDoubledDownHand1 && !game.hasDoubledDownHand2, "Cannot hit after doubling down.");

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
            revert("Invalid hand ID.");
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
                        if (_calculateHandValue(game.playerHand2) > 0 && !game.hasDoubledDownHand2) {
                        } else {
                            game.state = GameState.DealerTurn;
                            _dealerPlay(msg.sender);
                        }
                    } else {
                        game.state = GameState.DealerTurn;
                        _dealerPlay(msg.sender);
                    }
                } else {
                    _endGame(msg.sender, "Player Busts", 0);
                }
                return;
            } else if (playerValue == 21) {
                emit PlayerStood(msg.sender, _handId);
                if (game.hasSplit) {
                    if (_handId == 1) {
                        game.playerHand1Done = true;
                        if (_calculateHandValue(game.playerHand2) > 0 && !game.hasDoubledDownHand2) {
                        } else {
                            game.state = GameState.DealerTurn;
                            _dealerPlay(msg.sender);
                        }
                    } else {
                        game.state = GameState.DealerTurn;
                        _dealerPlay(msg.sender);
                    }
                } else {
                    game.state = GameState.DealerTurn;
                    _dealerPlay(msg.sender);
                }
                return;
            }
        }
    }

    function stand(uint8 _handId) external inState(GameState.PlayerTurn) {
        PlayerGame storage game = playerGames[msg.sender];
        require(!game.hasDoubledDownHand1 && !game.hasDoubledDownHand2, "Cannot stand after doubling down.");

        if (_handId == 1) {
            require(!game.playerHand1Done, "Hand 1 is already done.");
            game.playerHand1Done = true;
            emit PlayerStood(msg.sender, 1);
            if (game.hasSplit && _calculateHandValue(game.playerHand2) > 0) {
            } else {
                game.state = GameState.DealerTurn;
                _dealerPlay(msg.sender);
            }
        } else if (_handId == 2 && game.hasSplit) {
            require(game.playerHand1Done, "Hand 1 must be done before playing Hand 2.");
            emit PlayerStood(msg.sender, 2);
            game.state = GameState.DealerTurn;
            _dealerPlay(msg.sender);
        } else {
            revert("Invalid hand ID or no split hand to stand on.");
        }
    }

    function doubleDown(uint8 _handId) external payable inState(GameState.PlayerTurn) {
        PlayerGame storage game = playerGames[msg.sender];
        require(!game.hasDoubledDownHand1 && !game.hasDoubledDownHand2, "Already doubled down on a hand.");

        uint8[] storage currentHand;
        if (_handId == 1) {
            require(game.playerHand.length == 2, "Can only double down on initial two cards.");
            require(msg.value == game.bet, "Must double the original bet for hand 1.");
            game.bet += msg.value;
            game.hasDoubledDownHand1 = true;
            currentHand = game.playerHand;
        } else if (_handId == 2 && game.hasSplit) {
            require(game.playerHand2.length == 2, "Can only double down on initial two cards for split hand.");
            require(msg.value == game.bet2, "Must double the original bet for hand 2.");
            game.bet2 += msg.value;
            game.hasDoubledDownHand2 = true;
            currentHand = game.playerHand2;
        } else {
            revert("Invalid hand ID or no split hand to double down on.");
        }

        _dealCard(msg.sender, true, _handId);
        emit DoubleDown(msg.sender, _handId == 1 ? game.bet : game.bet2, _handId);

        uint256 playerValue = _calculateHandValue(currentHand);
        if (playerValue > 21) {
            emit PlayerBust(msg.sender, playerValue, _handId);
            if (game.hasSplit) {
                if (_handId == 1) {
                    game.playerHand1Done = true;
                    if (_calculateHandValue(game.playerHand2) > 0 && !game.hasDoubledDownHand2) {
                    } else {
                        game.state = GameState.DealerTurn;
                        _dealerPlay(msg.sender);
                    }
                } else {
                    game.state = GameState.DealerTurn;
                    _dealerPlay(msg.sender);
                }
            } else {
                _endGame(msg.sender, "Player Busts", 0);
            }
        } else {
            emit PlayerStood(msg.sender, _handId);
            if (game.hasSplit) {
                if (_handId == 1) {
                    game.playerHand1Done = true;
                    if (_calculateHandValue(game.playerHand2) > 0 && !game.hasDoubledDownHand2) {
                    } else {
                        game.state = GameState.DealerTurn;
                        _dealerPlay(msg.sender);
                    }
                } else {
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

        game.playerHand2.push(game.playerHand[1]);
        game.playerHand.pop();

        _dealCard(msg.sender, true, 1);
        _dealCard(msg.sender, true, 2);

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
        require(
            game.state == GameState.Idle ||
            game.state == GameState.GameOver ||
            game.state == GameState.BetPlaced, // Allow resetting if bet placed but not dealt
            "Cannot reset game in current active playing state. Finish the round or wait for it to conclude."
        );

        game.bet = 0;
        game.playerHand = new uint8[](0);
        game.dealerHand = new uint8[](0);
        game.state = GameState.Idle;
        game.playerStood = false;
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

        uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender, game.lastBlockNumber)));
        game.lastBlockNumber = block.number;

        uint8 card = uint8((randomNumber % 13) + 1);
        if (card > 10) {
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
        } else {
            game.dealerHand.push(card);
            emit DealerCardDealt(_player, card, _calculateHandValue(game.dealerHand));
        }
        return card;
    }

    function _calculateHandValue(uint8[] memory _hand) internal pure returns (uint256) {
        uint256 value = 0;
        uint256 numAces = 0;

        for (uint i = 0; i < _hand.length; i++) {
            if (_hand[i] == 1) {
                numAces++;
                value += 11;
            } else {
                value += _hand[i];
            }
        }

        while (value > 21 && numAces > 0) {
            value -= 10;
            numAces--;
        }
        return value;
    }

    function _dealerPlay(address _player) internal {
        PlayerGame storage game = playerGames[_player];
        uint256 dealerValue = _calculateHandValue(game.dealerHand);

        if (game.dealerHand.length == 1) {
             _dealCard(msg.sender, false, 0);
             dealerValue = _calculateHandValue(game.dealerHand);
        }

        if (game.insuranceTaken) {
            if (dealerValue == 21 && game.dealerHand.length == 2) {
                (bool success, ) = payable(msg.sender).call{value: game.insuranceBet * 3}("");
                require(success, "Failed to send insurance winnings.");
            } else {
            }
        }

        while (dealerValue < 17) {
            _dealCard(msg.sender, false, 0);
            dealerValue = _calculateHandValue(game.dealerHand);
        }

        if (dealerValue > 21) {
            emit DealerBust(_player, dealerValue);
            _resolveGameOutcome(_player, true);
        } else {
            _resolveGameOutcome(_player, false);
        }
    }

    function _resolveGameOutcome(address _player, bool _dealerBusted) internal {
        PlayerGame storage game = playerGames[_player];
        uint256 dealerValue = _calculateHandValue(game.dealerHand);

        _determineHandOutcome(_player, game.playerHand, game.bet, 1, dealerValue, _dealerBusted);

        if (game.hasSplit) {
            _determineHandOutcome(_player, game.playerHand2, game.bet2, 2, dealerValue, _dealerBusted);
        }

        game.state = GameState.GameOver;
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
            winnings = 0;
        } else if (_dealerBusted) {
            result = string.concat("Hand ", _uint8ToString(_handId), ": Dealer Busts! You Win!");
            winnings = _bet * 2;
        } else if (playerValue > _dealerValue) {
            result = string.concat("Hand ", _uint8ToString(_handId), ": You Win!");
            winnings = _bet * 2;
        } else if (playerValue < _dealerValue) {
            result = string.concat("Hand ", _uint8ToString(_handId), ": Dealer Wins");
            winnings = 0;
        } else {
            result = string.concat("Hand ", _uint8ToString(_handId), ": Push (It's a Tie)");
            winnings = _bet;
        }

        if (winnings > 0) {
            (bool success, ) = payable(_player).call{value: winnings}("");
            require(success, string.concat("Failed to send Ether for Hand ", _uint8ToString(_handId)));
        }
        emit GameResult(_player, result, winnings);
    }

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

    function _endGame(address _player, string memory _result, uint256 _winnings) internal {
        PlayerGame storage game = playerGames[_player];
        game.state = GameState.GameOver;
        if (_winnings > 0) {
            (bool success, ) = payable(msg.sender).call{value: _winnings}("");
            require(success, "Failed to send Ether.");
        }
        emit GameResult(_player, _result, _winnings);
    }

    function withdrawAll() external {
        payable(msg.sender).transfer(address(this).balance);
    }
}

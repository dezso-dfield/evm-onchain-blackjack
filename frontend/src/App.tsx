import React, { useState, useEffect, useCallback } from 'react';
import { ethers, Contract } from 'ethers';
import abi from './Blackjack.json';
import './App.css';


const CONTRACT_ADDRESS = 'Contact_address';

const GameState = {
  Idle: 0,
  BetPlaced: 1,
  PlayerTurn: 2,
  DealerTurn: 3,
  GameOver: 4,
};

const getCardDisplayName = (cardValue) => {
  if (cardValue === 1) return 'A';
  if (cardValue === 11) return 'J';
  if (cardValue === 12) return 'Q';
  if (cardValue === 13) return 'K';
  return cardValue.toString();
};

function App() {
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [contract, setContract] = useState(null);
  const [account, setAccount] = useState(null);
  const [betAmount, setBetAmount] = useState('');
  const [playerHand, setPlayerHand] = useState([]);
  const [dealerHand, setDealerHand] = useState([]);
  const [playerHand2, setPlayerHand2] = useState([]);
  const [playerHandValue, setPlayerHandValue] = useState(0);
  const [dealerHandValue, setDealerHandValue] = useState(0);
  const [playerHand2Value, setPlayerHand2Value] = useState(0);
  const [gameState, setGameState] = useState(GameState.Idle);
  const [message, setMessage] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [playerBalance, setPlayerBalance] = useState('0.0');
  const [contractBalance, setContractBalance] = useState('0.0');
  const [gameData, setGameData] = useState({});

  const fetchBalances = useCallback(async () => {
    if (provider && account) {
      try {
        const playerEthBalance = await provider.getBalance(account);
        setPlayerBalance(ethers.formatEther(playerEthBalance));
      } catch (error) {
        console.error("Error fetching player balance:", error);
      }
    }
    if (provider && CONTRACT_ADDRESS) {
      try {
        const contractEthBalance = await provider.getBalance(CONTRACT_ADDRESS);
        setContractBalance(ethers.formatEther(contractEthBalance));
      } catch (error) {
        console.error("Error fetching contract balance:", error);
      }
    }
  }, [provider, account]);


  const connectWallet = async () => {
    if (window.ethereum) {
      try {
        setIsLoading(true);
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        const selectedAccount = accounts[0];
        setAccount(selectedAccount);

        const newProvider = new ethers.BrowserProvider(window.ethereum);
        setProvider(newProvider);

        const newSigner = await newProvider.getSigner();
        setSigner(newSigner);

        const blackjackContract = new Contract(CONTRACT_ADDRESS, abi, newSigner);
        setContract(blackjackContract);

        setMessage('Wallet connected!');
      } catch (error) {
        console.error("Error connecting to wallet:", error);
        setMessage(`Error connecting: ${error.message}`);
      } finally {
        setIsLoading(false);
      }
    } else {
      setMessage("MetaMask is not installed. Please install it to play.");
    }
  };

  const fetchGameState = useCallback(async () => {
    if (contract && account) {
      try {
        const game = await contract.playerGames(account);
        setGameData(game);
        console.log("Current Game State:", Number(game.state));

        setBetAmount(ethers.formatEther(game.bet));
        setGameState(Number(game.state));

        const playerHandRaw = await contract.getPlayerHand(account);
        setPlayerHand(playerHandRaw.map(Number));

        const dealerHandRaw = await contract.getDealerHand(account);
        setDealerHand(dealerHandRaw.map(Number));

        const playerHand2Raw = await contract.getPlayerHand2(account);
        setPlayerHand2(playerHand2Raw.map(Number));

        const pValue = await contract.getHandValue(account, true);
        setPlayerHandValue(Number(pValue));

        const dValue = await contract.getHandValue(account, false);
        setDealerHandValue(Number(dValue));

        const p2Value = await contract.getHandValue2(account);
        setPlayerHand2Value(Number(p2Value));


        if (Number(game.state) === GameState.GameOver) {
          setMessage('Game Over. Check console for result event.');
        } else if (Number(game.state) === GameState.PlayerTurn) {
            if (game.hasSplit && !game.playerHand1Done) {
                setMessage('Your turn for Hand 1: Hit, Stand, or Double Down?');
            } else if (game.hasSplit && game.playerHand1Done && playerHand2Raw.length > 0) {
                setMessage('Your turn for Hand 2: Hit, Stand, or Double Down?');
            } else {
                setMessage('Your turn: Hit, Stand, Double Down, or Split?');
            }
        } else if (Number(game.state) === GameState.BetPlaced) {
          setMessage('Bet placed. Click Deal Cards to start!');
        } else if (Number(game.state) === GameState.Idle) {
          setMessage('Place your bet to start a new game!');
        }
      } catch (error) {
        console.error("Error fetching game state:", error);
        setMessage(`Error fetching game state: ${error.message}`);
      }
    }
  }, [contract, account]);

  useEffect(() => {
    if (contract && account) {
      const handleGameStarted = (player, betAmount) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Game started! Bet: ${ethers.formatEther(betAmount)} ETH`);
          fetchGameState();
          fetchBalances();
        }
      };

      const handlePlayerCardDealt = (player, card, handValue, handId) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Hand ${Number(handId)} dealt: ${getCardDisplayName(Number(card))}. Value: ${Number(handValue)}`);
          fetchGameState();
        }
      };

      const handleDealerCardDealt = (player, card, handValue) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Dealer dealt: ${getCardDisplayName(Number(card))}. Value: ${Number(handValue)}`);
          fetchGameState();
        }
      };

      const handlePlayerStood = (player, handId) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Player stood on Hand ${Number(handId)}. ${gameData.hasSplit && !gameData.playerHand1Done ? 'Now playing Hand 2...' : 'Dealer is playing...'}`);
          fetchGameState();
        }
      };

      const handlePlayerBust = (player, finalHandValue, handId) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Hand ${Number(handId)} Busts! Final Hand: ${Number(finalHandValue)}. You Lose!`);
          fetchGameState();
          fetchBalances();
        }
      };

      const handleDealerBust = (player, finalHandValue) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Dealer Busts! Final Hand: ${Number(finalHandValue)}. You Win!`);
          fetchGameState();
          fetchBalances();
        }
      };

      const handleGameResult = (player, result, winnings) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Game Result: ${result}. Winnings: ${ethers.formatEther(winnings)} ETH`);
          fetchGameState();
          fetchBalances();
        }
      };

      const handleInsuranceTaken = (player, amount) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Insurance taken for ${ethers.formatEther(amount)} ETH.`);
          fetchGameState();
          fetchBalances();
        }
      };

      const handleDoubleDown = (player, newBet, handId) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Hand ${Number(handId)} doubled down! New bet: ${ethers.formatEther(newBet)} ETH.`);
          fetchGameState();
          fetchBalances();
        }
      };

      const handleSplit = (player, betAmount) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage(`Hands split! New bet on Hand 2: ${ethers.formatEther(betAmount)} ETH.`);
          fetchGameState();
          fetchBalances();
        }
      };

      const handleGameReset = (player) => {
        if (player.toLowerCase() === account.toLowerCase()) {
          setMessage('Game state reset to Idle.');
          fetchGameState();
          fetchBalances();
        }
      };


      contract.on('GameStarted', handleGameStarted);
      contract.on('PlayerCardDealt', handlePlayerCardDealt);
      contract.on('DealerCardDealt', handleDealerCardDealt);
      contract.on('PlayerStood', handlePlayerStood);
      contract.on('PlayerBust', handlePlayerBust);
      contract.on('DealerBust', handleDealerBust);
      contract.on('GameResult', handleGameResult);
      contract.on('InsuranceTaken', handleInsuranceTaken);
      contract.on('DoubleDown', handleDoubleDown);
      contract.on('Split', handleSplit);
      contract.on('GameReset', handleGameReset);


      return () => {
        contract.off('GameStarted', handleGameStarted);
        contract.off('PlayerCardDealt', handlePlayerCardDealt);
        contract.off('DealerCardDealt', handleDealerCardDealt);
        contract.off('PlayerStood', handlePlayerStood);
        contract.off('PlayerBust', handlePlayerBust);
        contract.off('DealerBust', handleDealerBust);
        contract.off('GameResult', handleGameResult);
        contract.off('InsuranceTaken', handleInsuranceTaken);
        contract.off('DoubleDown', handleDoubleDown);
        contract.off('Split', handleSplit);
        contract.off('GameReset', handleGameReset);
      };
    }
  }, [contract, account, fetchGameState, fetchBalances, gameData]);

  useEffect(() => {
    fetchGameState();
    fetchBalances();
  }, [fetchGameState, fetchBalances]);


  useEffect(() => {
    if (window.ethereum) {
      const handleAccountsChanged = (accounts) => {
        if (accounts.length > 0) {
          setAccount(accounts[0]);
          setMessage('Account changed. Refreshing game state...');
          connectWallet();
        } else {
          setAccount(null);
          setProvider(null);
          setSigner(null);
          setContract(null);
          setMessage('Wallet disconnected.');
        }
      };

      window.ethereum.on('accountsChanged', handleAccountsChanged);
      window.ethereum.on('chainChanged', () => {
        setMessage('Network changed. Please reconnect wallet.');
        setAccount(null);
        setProvider(null);
        setSigner(null);
        setContract(null);
      });

      return () => {
        window.ethereum.removeListener('accountsChanged', handleAccountsChanged);
        window.ethereum.removeListener('chainChanged', () => {});
      };
    }
  }, []);

  const handlePlaceBet = async () => {
    if (!contract || !betAmount) {
      setMessage('Please connect wallet and enter a bet amount.');
      return;
    }
    try {
      setIsLoading(true);
      setMessage('Placing bet...');
      const tx = await contract.placeBet({ value: ethers.parseEther(betAmount) });
      await tx.wait();
      setMessage('Bet placed successfully! Dealing cards...');
      fetchGameState();
      fetchBalances();
    } catch (error) {
      console.error("Error placing bet:", error);
      setMessage(`Error placing bet: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleDealInitialCards = async () => {
    if (!contract) return;
    try {
      setIsLoading(true);
      setMessage('Dealing initial cards...');
      const tx = await contract.dealInitialCards({ gasLimit: 1_000_000 });
      await tx.wait();
      setMessage('Cards dealt!');
      fetchGameState();
    } catch (error) {
      console.error("Error dealing cards:", error);
      setMessage(`Error dealing cards: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleHit = async (handId) => {
    if (!contract) return;
    try {
      setIsLoading(true);
      setMessage(`Hitting Hand ${handId}...`);
      const tx = await contract.hitMultiple(1, handId, { gasLimit: 1_000_000 });
      await tx.wait();
      setMessage(`Hand ${handId} hit!`);
      fetchGameState();
    } catch (error) {
      console.error("Error hitting:", error);
      setMessage(`Error hitting: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleStand = async (handId) => {
    if (!contract) return;
    try {
      setIsLoading(true);
      setMessage(`Standing on Hand ${handId}...`);
      const tx = await contract.stand(handId, { gasLimit: 1_000_000 });
      await tx.wait();
      setMessage(`Hand ${handId} stood. Waiting for dealer...`);
      fetchGameState();
    } catch (error) {
      console.error("Error standing:", error);
      setMessage(`Error standing: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleDoubleDown = async (handId) => {
    if (!contract || !gameData.bet) return;
    try {
      setIsLoading(true);
      setMessage(`Doubling down on Hand ${handId}...`);
      const betForHand = handId === 1 ? gameData.bet : gameData.bet2;
      const tx = await contract.doubleDown(handId, { value: betForHand, gasLimit: 5_000_000 });
      await tx.wait();
      setMessage(`Hand ${handId} doubled down!`);
      fetchGameState();
      fetchBalances();
    } catch (error) {
      console.error("Error doubling down:", error);
      setMessage(`Error doubling down: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleSplit = async () => {
    if (!contract || !gameData.bet) return;
    try {
      setIsLoading(true);
      setMessage('Splitting hands...');
      const tx = await contract.split({ value: gameData.bet, gasLimit: 5_000_000 });
      await tx.wait();
      setMessage('Hands split!');
      fetchGameState();
      fetchBalances();
    } catch (error) {
      console.error("Error splitting:", error);
      setMessage(`Error splitting: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleTakeInsurance = async () => {
    if (!contract || !gameData.bet) return;
    try {
      setIsLoading(true);
      setMessage('Taking insurance...');
      const insuranceCost = gameData.bet / 2n;
      const tx = await contract.takeInsurance({ value: insuranceCost, gasLimit: 5_000_000 });
      await tx.wait();
      setMessage('Insurance taken!');
      fetchGameState();
      fetchBalances();
    } catch (error) {
      console.error("Error taking insurance:", error);
      setMessage(`Error taking insurance: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleWithdrawAll = async () => {
    if (!contract) return;
    try {
      setIsLoading(true);
      setMessage('Withdrawing funds...');
      const tx = await contract.withdrawAll();
      await tx.wait();
      setMessage('Funds withdrawn successfully!');
      fetchBalances();
    } catch (error) {
      console.error("Error withdrawing funds:", error);
      setMessage(`Error withdrawing funds: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleResetGame = async () => {
    if (!contract) return;
    try {
      setIsLoading(true);
      setMessage('Attempting to reset game...');
      const tx = await contract.resetGame({ gasLimit: 300_000 });
      await tx.wait();
      setMessage('Game reset to Idle!');
      fetchGameState();
      fetchBalances();
    } catch (error) {
      console.error("Error resetting game:", error);
      setMessage(`Error resetting game: ${error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const getCurrentHandId = () => {
    if (gameData.hasSplit && !gameData.playerHand1Done) {
      return 1;
    } else if (gameData.hasSplit && gameData.playerHand1Done && playerHand2.length > 0) {
      return 2;
    }
    return 1;
  };

  const currentHandId = getCurrentHandId();
  const currentHandCards = currentHandId === 1 ? playerHand : playerHand2;
  const currentHandValue = currentHandId === 1 ? playerHandValue : playerHand2Value;
  const hasDoubledDownCurrentHand = currentHandId === 1 ? gameData.hasDoubledDownHand1 : gameData.hasDoubledDownHand2;


  const canHit = gameState === GameState.PlayerTurn && !hasDoubledDownCurrentHand;
  const canStand = gameState === GameState.PlayerTurn && !hasDoubledDownCurrentHand;
  const canDoubleDown = gameState === GameState.PlayerTurn && currentHandCards.length === 2 && !hasDoubledDownCurrentHand;
  const canSplit = gameState === GameState.PlayerTurn && !gameData.hasSplit && playerHand.length === 2 && playerHand[0] === playerHand[1];
  const canTakeInsurance = gameState === GameState.PlayerTurn && gameData.dealerHasAce && !gameData.insuranceTaken;


  return (
    <div className="blackjack-container">
      <div className="game-card">
        <h1 className="game-title">
          On-Chain Blackjack
        </h1>

        {!account ? (
          <button
            onClick={connectWallet}
            className="btn btn-connect"
            disabled={isLoading}
          >
            {isLoading ? 'Connecting...' : 'Connect Wallet'}
          </button>
        ) : (
          <div className="account-info">
            <p className="account-address">Connected: <span className="account-address-mono">{account.substring(0, 6)}...{account.substring(account.length - 4)}</span></p>
            <p className="balance-text">Your Balance: <span className="player-balance">{playerBalance} ETH</span></p>
            <p className="balance-text">Contract Balance: <span className="contract-balance">{contractBalance} ETH</span></p>
            <p className="message-text">{message}</p>
          </div>
        )}

        {account && (
          <>
            <div className="bet-section">
              <h2 className="section-title">Place Your Bet</h2>
              <div className="bet-input-group">
                <input
                  type="number"
                  placeholder="Bet Amount (ETH)"
                  value={betAmount}
                  onChange={(e) => setBetAmount(e.target.value)}
                  className="bet-input"
                  min="0.0001"
                  step="0.0001"
                  disabled={gameState !== GameState.Idle && gameState !== GameState.GameOver}
                />
                <button
                  onClick={handlePlaceBet}
                  className="btn btn-place-bet"
                  disabled={isLoading || !betAmount || (gameState !== GameState.Idle && gameState !== GameState.GameOver)}
                >
                  {isLoading ? 'Processing...' : 'Place Bet'}
                </button>
              </div>
            </div>

            <div className="hands-grid">
              <div className="hand-card">
                <h2 className="hand-title">Dealer's Hand ({dealerHandValue})</h2>
                <div className="cards-display">
                  {dealerHand.map((card, index) => (
                    <div key={index} className="card">
                      {getCardDisplayName(card)}
                    </div>
                  ))}
                </div>
              </div>

              <div className="hand-card">
                <h2 className="hand-title">Your Hand ({playerHandValue})</h2>
                <div className="cards-display">
                  {playerHand.map((card, index) => (
                    <div key={index} className="card">
                      {getCardDisplayName(card)}
                    </div>
                  ))}
                </div>
              </div>

              {gameData.hasSplit && playerHand2.length > 0 && (
                <div className="hand-card">
                  <h2 className="hand-title">Your Split Hand ({playerHand2Value})</h2>
                  <div className="cards-display">
                    {playerHand2.map((card, index) => (
                      <div key={index} className="card">
                        {getCardDisplayName(card)}
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>

            <div className="game-actions">
              {(gameState === GameState.BetPlaced) && (
                <button
                  onClick={handleDealInitialCards}
                  className="btn btn-deal"
                  disabled={isLoading}
                >
                  {isLoading ? 'Dealing...' : 'Deal Cards'}
                </button>
              )}

              {gameState === GameState.PlayerTurn && (
                <>
                  <button
                    onClick={() => handleHit(currentHandId)}
                    className="btn btn-hit"
                    disabled={isLoading || !canHit}
                  >
                    {isLoading ? 'Hitting...' : 'Hit'}
                  </button>
                  <button
                    onClick={() => handleStand(currentHandId)}
                    className="btn btn-stand"
                    disabled={isLoading || !canStand}
                  >
                    {isLoading ? 'Standing...' : 'Stand'}
                  </button>
                  <button
                    onClick={() => handleDoubleDown(currentHandId)}
                    className="btn btn-double-down"
                    disabled={isLoading || !canDoubleDown}
                  >
                    {isLoading ? 'Doubling Down...' : 'Double Down'}
                  </button>
                  <button
                    onClick={handleSplit}
                    className="btn btn-split"
                    disabled={isLoading || !canSplit}
                  >
                    {isLoading ? 'Splitting...' : 'Split'}
                  </button>
                  <button
                    onClick={handleTakeInsurance}
                    className="btn btn-insurance"
                    disabled={isLoading || !canTakeInsurance}
                  >
                    {isLoading ? 'Taking Insurance...' : 'Take Insurance'}
                  </button>
                </>
              )}
            </div>

            <div className="withdraw-section">
              <button
                onClick={handleWithdrawAll}
                className="btn btn-withdraw"
                disabled={isLoading}
              >
                Withdraw Contract Funds (Owner Only)
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

export default App;

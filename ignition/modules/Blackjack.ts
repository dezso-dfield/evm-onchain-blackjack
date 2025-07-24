import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const BlackjackModule = buildModule("BlackjackModule", (m) => {
  const blackjack = m.contract("Blackjack");

  return { blackjack };
});

export default BlackjackModule;

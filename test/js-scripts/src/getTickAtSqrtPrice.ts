import Decimal from "decimal.js";
import { ethers } from "ethers";

const sqrtPriceArray = process.argv[2].split(",");
const resultsArray = [];
for (let sqrtPrice of sqrtPriceArray) {
  const jsResult = new Decimal(sqrtPrice).div(new Decimal(2).pow(96)).pow(2).log(1.0001).floor().toFixed(0);
  resultsArray.push(jsResult);
}
process.stdout.write(ethers.utils.defaultAbiCoder.encode(["int256[]"], [resultsArray]));

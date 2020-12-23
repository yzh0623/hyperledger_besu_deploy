var args = process.argv.splice(2);
const Web3 = require('web3');

//Web3 initialization (should point to the JSON-RPC endpoint)
const web3 = new Web3(new Web3.providers.HttpProvider('http://127.0.0.1:8545'));

var V3KeyStore = web3.eth.accounts.encrypt(args[0], args[1]);
console.log(JSON.stringify(V3KeyStore));
process.exit();

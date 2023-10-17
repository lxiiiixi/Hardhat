const { keccak256 } = require("ethers");


function getSelector(functionSignature) {
    return keccak256(functionSignature).slice(0, 10);
}


function main() {
    const targetSelector = "0xb15b76ee"
    for (let i = 1; i < 10000; i++) {
        const testSignature = `testFunc${i}(uint16,uint256,uint256,address)`;
        if (getSelector(testSignature) === targetSelector) {
            console.log(`Found matching signature: ${testSignature}`);
            break;
        }
    }
}
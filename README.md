<img src="https://kepler.gomusiclive.com/assets/xavemarket/artists/xavemarket-artist.jpg" alt="https://kepler.gomusiclive.com/assets/xaveproject/artists/xavemarket-artist.jpg"  width=120 align=left />


## Official Xave Project public repository

www.xavecoin.com / hello@xavecoin.com

To validate the authenticity of this repository, please send an email to the official project's mailbox above with the current URL on the body.

---

# SalesProxy

## Purpose
- Handle the exchange of non-fungible tokens (ERC721) and native currency (eth), favoring gas efficiency when possible.
- Allow NFT creators to mint their NFTs or choose *lazy minting*.
- Distribute payments into one or more accounts.
- Validate sales using digital signatures.

## Description
NFT creators can choose to publish their NFTs by minting the NFT first or by using the lazy minting technique.   
If lazy minting, when buyers purchase an NFT (not minted) they also pay for the gas needed to mint the NFT to their account. This way, the NFT creator can publish and sell his/her work without any up-front costs.

Minting straight to the buyer, implies the NFT creator does not show on the blockchain as the first NFT owner.
This leaves no prove of the actual NFT creator. The alternative would have been to mint the token first to the NFT creator and then transfer it to the buyer. But that would mean writing two transactions on the blockchain instead of one, making it more expesive for the buyer.  
In order to not lose the NFT creator completely, SalesProxy only mints token IDs that can be traced back to the NFT creator's address. It accomplishes that, by hashing the address using keccak256 and converting each resulting byte to its number representation. Then append every number in the order they came, and take the first X amount of numbers.  
The resulting number it used as the token ID prefix.

The total payment (gas fee not included) can be split into more than one account (ie: NTF owner + broker fee + donation + other )
The NFT owner agrees to the payment distribution by signing with his/her wallet, at publishing time.
Then a trusted account (SalesProxy's admin) also signs the same publication.
SalesProxy uses both signatures to validate the purchase.

For NFT tokens already minted, the NFT owner must approve SalesProxy to transfer the NFT on its behalf. SalesProxy will make the transfer, when someone buys the NFT at the price that was set and signed by NFT owner.

To transfer the native currency (eth), SalesProxy uses the push method instead of the usually preferred pull method.
With the pull method, the NFT owner would need to spend gas to pull the eth from SalesProxy.


## Calling SalesProxy's functions from React using ethers.js

### NFT creator mints the NFT token on TokenNFT 

```
const provider = new ethers.providers.Web3Provider(window.ethereum)
const signer = provider.getSigner()
const proxy = new ethers.Contract(salesProxyAddress, SalesProxy.abi, signer)

//tokenAddress must be address of TokenNFT
const tx = await proxy.mintToken(tokenAddress, mintToAddress, mintTokenId, mintURI)
await tx.wait()
```

### Grant minter role to SalesProxy

```
const provider = new ethers.providers.Web3Provider(window.ethereum)
const token = new ethers.Contract(tokenNFTAddress, TokenNFT.abi, provider)

const tx = await token.grantRole(token.MINTER_ROLE(), salesProxyAddress)
await tx.wait()
```

### NFT creator approves SalesProxy to transfer his/her NFT

```
tx = await token.setApprovalForAll(salesProxyAddress,true)
await tx.wait()
```

### List all the tokens at TokenNFT

```
const provider = new ethers.providers.Web3Provider(window.ethereum)
const token = new ethers.Contract(tokenNFTAddress, TokenNFT.abi, provider)

const totTokens = await token.totalSupply()
var tokenId
for (let i = 0; i < totTokens; i++) {
    tokenId = await token.tokenByIndex(i)
    tokenList.push(
        tokenId.toNumber() 
        + " | " + await token.ownerOf(tokenId) 
        + " | " +  await token.tokenURI(tokenId) 
        )
}
const list = tokenList.map((item) => <li key={item}>{item}</li>)
setTokenList(list) 
```

### Funtion to parse the NFT creator's token ID prefix from its address

```
function parseTokenIdPrefix(sellerAddress){
    /**
    * @dev hash the seller address with keccak256 and convert it to Uint8Array.
    * Convert each number in Uint8Array to a string and return 
    * the first SELLER_TOKEN_ID_LENGTH characters
    */
    const addressHashed = ethers.utils.keccak256(sellerAddress)
    const addressHashedArray = ethers.utils.arrayify(addressHashed)

    let sellerPrefix = ""
    addressHashedArray.forEach(element => {
        sellerPrefix = sellerPrefix + element.toString()
    });
    return sellerPrefix.slice(0,SELLER_TOKEN_ID_LENGTH)
}
```

### Sign the message and store the signature to be used at purchase time
The message must be signed and stored twice. First by the NFT seller and
then by the SalesProxy's admin.

```
// Array with payment dritribution accounts
var pymtDistAddress = []
pymtDistAddress.push(toAddress1)
pymtDistAddress.push(toAddress2)

// Array with payment dritribution amounts
// If ammount are expressed in eth, then convert to wei
var pymtDistAmt = []
pymtDistAmt.push(ethers.utils.parseEther(toAddressAmt1))
pymtDistAmt.push(ethers.utils.parseEther(toAddressAmt2))

let hash = ethers.utils.solidityKeccak256(
            ['address', 'uint256','address' ,'address[]','uint256[]'] ,
            [tokenAddress, tokenId, salesProxyAddress, pymtDistAddress, pymtDistAmt]
            )

// Convert to hex
hash  = Buffer.from(hash.slice(2), 'hex')

// The signature must be stored to be used latter 
const signature = await signer.signMessage(hash)
```

### The buyer puchases the NFT 

```
// Create the parameters for the purchase.
// They must match the seller and admin stored signatures
var pymtDistAddress = []
pymtDistAddress.push(toAddress1)
pymtDistAddress.push(toAddress2)

var pymtDistAmt = []
pymtDistAmt.push(ethers.utils.parseEther(toAddressAmt1))
pymtDistAmt.push(ethers.utils.parseEther(toAddressAmt2))

// Get the total amount the buyer agrees to pay.
// Must be equal to toAddressAmt1 + toAddressAmt2 
const ethAmt = ethers.utils.parseEther(totalAmtEth)

//Append eth to the message
let overrides = {
    value: ethAmt,
}

// sellerSignature = previously stored seller's signature.
// adminSignature = previously stored admin's signature.
// Note that salesProxyAddress was included on the signed message,
// but not on the parameters of the fuction proxy.buyNFTWithNative.
// SalesProxy decodes the signatures using address(this) to prevent
// signatures from other contexts.
const tx = await proxy.buyNFTWithNative(
                tokenAddress,
                trasnferTokenId,
                pymtDistAddress,
                pymtDistAmt,
                sellerSignature,
                adminSignature,
                isMinted,
                mintURI,
                overrides
                )
await tx.wait()
```

## Disclaimer

The material embodied in this software is provided to you "as-is" and without warranty of any kind, express, implied or otherwise, including without limitation, any warranty of fitness for a particular purpose. In no event shall Xave Project be liable to you or anyone else for any direct, special, incidental, indirect or consequential damages of any kind, or any damages whatsoever, including without limitation, loss of profit, loss of use, savings or revenue, or the claims of third parties, whether or not Xave Project has been advised of the possibility of such loss, however caused and on any theory of liability, arising out of or in connection with the possession, use or performance of this software.

More on this on https://xavecoin.com/termsconditions/



## License

[![License: LGPL v3](https://img.shields.io/badge/License-LGPL%20v3-blue.svg)](https://www.gnu.org/licenses/lgpl-3.0)

This program is free software; you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation; either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
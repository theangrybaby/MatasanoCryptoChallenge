#!/usr/bin/ruby

# Set 3 Function Library

# Pull in Set 2 Library

require '../Set 2/set2Lib.rb'

# Challenge 17
def cbcPaddingOracleEncrypt(key)
	
	randomStrArray = []
	
	randomStrArray << "MDAwMDAwTm93IHRoYXQgdGhlIHBhcnR5IGlzIGp1bXBpbmc="
	randomStrArray << "MDAwMDAxV2l0aCB0aGUgYmFzcyBraWNrZWQgaW4gYW5kIHRoZSBWZWdhJ3MgYXJlIHB1bXBpbic="
	randomStrArray << "MDAwMDAyUXVpY2sgdG8gdGhlIHBvaW50LCB0byB0aGUgcG9pbnQsIG5vIGZha2luZw=="
	randomStrArray << "MDAwMDAzQ29va2luZyBNQydzIGxpa2UgYSBwb3VuZCBvZiBiYWNvbg=="
	randomStrArray << "MDAwMDA0QnVybmluZyAnZW0sIGlmIHlvdSBhaW4ndCBxdWljayBhbmQgbmltYmxl"
	randomStrArray << "MDAwMDA1SSBnbyBjcmF6eSB3aGVuIEkgaGVhciBhIGN5bWJhbA=="
	randomStrArray << "MDAwMDA2QW5kIGEgaGlnaCBoYXQgd2l0aCBhIHNvdXBlZCB1cCB0ZW1wbw=="
	randomStrArray << "MDAwMDA3SSdtIG9uIGEgcm9sbCwgaXQncyB0aW1lIHRvIGdvIHNvbG8="
	randomStrArray << "MDAwMDA4b2xsaW4nIGluIG15IGZpdmUgcG9pbnQgb2g="
	randomStrArray << "MDAwMDA5aXRoIG15IHJhZy10b3AgZG93biBzbyBteSBoYWlyIGNhbiBibG93"
	
	
	str = randomStrArray[rand(0..randomStrArray.size-1)].unpack("m").join

	iv = randomAESKey16

	ct = encryptAES_CBC(str, key, iv)
	return [iv, ct]
end

# Simply validates CBC encryption padding
def cbcPaddingOracleDecrypt(ct, key, iv)
	# 16 byte block size for 128 bit key
	blockSize = 16
	pArray = Array.new
	ciphertxt = iv+ct
	
	
	breakIntoBlocks(ciphertxt, blockSize, 2) do |blockOne, blockTwo|
		plainBlock = decryptAES_ECB(blockTwo, key)
		xorBlock = blockXOR(plainBlock, blockOne)
		pArray << xorBlock
	end		
	
	paddedStr = pArray.join

	blocksize = key.length
	paddingCount = paddedStr[-1].ord	
	return false if paddingCount > 16
	paddingNums = paddedStr[-paddingCount..paddedStr.length]
	nonPaddedString = paddedStr[0..(((paddedStr.length-paddingCount))-1)]
	nonPaddedString = "" if paddingCount == blocksize
	return false if (paddingNums.length + nonPaddedString.length) % blocksize != 0
	return false if paddingNums.bytes.to_a.uniq.size != 1
	
	return true
end

# Here is the logic:

# It is easiest to think of this two blocks at a time.

# The first block is getting XOR'd with the decrypted intermediate 
# state of the second one.  The key to this attack is that we know the plain text
# and can modify the first block to find the intermediate states.

# Recall:
# INTERMEDIATE_STATE = PLAINTEXT XOR CIPHERTEXT(N-1)

# and therefore

# PLAINTEXT = CIPHERTEXT(N-1) XOR INTERMEDIATE_STATE

# We must first find the intermediate state of the last byte of plaintext.  Since we know 
# that valid padding only occurs when the last byte is \x01, we cycle through ATTACK_STR(N-1)[15]
# values until we validate the padding.  ATTACK_STR is 16 bytes in length and the other values 
# can be random.  Therefore we have the last byte of the intermediate state:

# INTERMEDIATE_STATE[15] = 01 XOR ATTACK_STR(N-1)[15]

# This INTERMEDIATE_STATE[15] byte can be XOR'd with the CIPHERTEXT(N-1)[15] byte to find the real 
# value of CIPHERTEXT(N)[15]!

# For the next byte we must realize that the plain text for the last two bytes of the PLAINTEXT
# will be \x02.  We know the intermediate state for the last byte but not the second-to-last byte.
# To find it, we construct an "attack block" with 14 random values (1 less than last time), our 
# unknown value and the previous INTERMEDIATE_STATE byte XOR'd with 02.

# When we validate we know that:

# INTERMEDIATE_STATE[14] = 02 XOR ATTACK_STR(N-1)[14]

# We can then take INTERMEDIATE_STATE[14] and XOR it with CIPHERTEXT(N-1)[14] to find the real value 
# of CIPHERTEXT(N)[14]!

# Continue until you are done with the block

def cbcPaddingOracleBlockAttack(cbcBlockOne, cbcBlockTwo, key)
	blocksize = key.length 
	
  
	message = ""
	intermediateArray = Array.new blocksize
	
	(1..16).each do |i|
		
		attackBlock = ""
		(blocksize-i).times {attackBlock.concat(rand(0..255).chr)}
		
		(0..255).each do |n|
			if i == 1
				# There is no intermediate stage developed yet
				currentAttackBlock=  attackBlock + n.chr + cbcBlockTwo
			else
				currentAttackBlock=  attackBlock + n.chr				
				currentAttackBlock += intermediateArray[(blocksize-(i-1))..(blocksize-1)].map{|x| (x.ord ^ i.ord).chr }.join
				currentAttackBlock += cbcBlockTwo	
			end
			
			raise "Invalid Length" if currentAttackBlock.length != 32
			# You can think of the first block acting as an IV since we only deal with two blocks at a time
			if cbcPaddingOracleDecrypt(currentAttackBlock, key, cbcBlockOne)
			
				intermediateArray[blocksize-i] = n.ord^i.ord
				
				message += (n.ord^i.ord ^ cbcBlockOne[blocksize-i].ord).chr	
				
			end
		end
	
	end
	return message.chars.to_a.reverse.join

	
end

def cbcPaddingOracleAttack(iv, ciphertxt, key)
	combinedCipherStr = [iv,ciphertxt].join
	message = []
	breakIntoBlocks(combinedCipherStr, key.length, 2) do |blockOne, blockTwo|
		message << cbcPaddingOracleBlockAttack(blockOne, blockTwo, key)
	end
	return message.join
end

# Challenge 18
def aesCTROperationBlock(targetStrBlock, nonce, i, key)
	blocksize = key.length
	raise "Wrong nonce size" if nonce.length != blocksize/2
	
	# Get counter (ctr) in \x01\x00 format (little endian)
	ctr = nonce + i.to_s.rjust(blocksize/2, "0").each_byte.to_a.reverse.map {|x| x.chr.to_i.chr}.join

	raise "Wrong lengths" if targetStrBlock.length != key.length
	
	# We only use AES encryption in CTR mode no matter what the actual CTR operation...cool
	# .. Wondering if you could use a hash like SHA256 in that case
	intermediateState = encryptAES_ECB(ctr,key)
	raise "Wrong Counter length" if ctr.length != intermediateState.length
	
	finalState = blockXOR(intermediateState, targetStrBlock)

	return finalState

end

def aesCTROperation(targetStr, nonce, key)
	message = []
	blocksize = key.length
	origLength = targetStr.length

	# breakIntoBlocks only works on lines of blocksize multiple lengths
	padLength = (targetStr.length.to_f/key.length.to_f).ceil*key.length
	targetStr += "\0"*(padLength-targetStr.length)

	i = 0
	breakIntoBlocks(targetStr, blocksize, 1) do |blockOne|
		message << aesCTROperationBlock(blockOne, nonce, i, key)
		i += 1
	end
	
	# Strip the padding we had
	return message.join[0..origLength-1]
end

# Challenge 19
def bruteForceCTR(ctArr,phraseToTest, i)
	keyMult = (ctArr[i].length.to_f/phraseToTest.length.to_f).ceil
	xorKey = (phraseToTest*keyMult)[0..ctArr[i].length-1]
	keystream = ctArr[i].chars.zip(xorKey.chars).map {|a,b| (a.ord^b.ord).chr}.join 
	i = 0
	ctArr.map do |x|
		begin
			p i, x.chars.zip(keystream.chars).map{|a,b| (a.ord^b.ord).chr}.join 
		rescue
			next 
		ensure 
			i += 1
		end
	end 
end 

# Challenge 21
class MT19937
	INITIALSTATE = 624
	def initialize(seed)
		@index = INITIALSTATE
		@mt = Array.new 
		@mt.push(seed)
		(1..INITIALSTATE-1).each do |i|
			@mt[i] = (1812433253 * (@mt[i-1] ^ (@mt[i-1] >> 30 )) + i) & 0xFFFFFFFF
		end 
	end 
	
	def genRandNum
		if @index >= INITIALSTATE
			twist
		end 
		
		y = @mt[@index]
		y = y ^ (y >> 11)
		y = y ^ (y << 7) & 2636928640
		y = y ^ (y << 15) & 4022730752
		y = y ^ (y >> 18)
		
		@index = @index + 1 
		
		return (y & 0xFFFFFFFF)
	end 
	
	def twist 
		(0..INITIALSTATE-1).each do |i| 
			y = ((@mt[i] & 0x80000000) | (@mt[(i+1) % INITIALSTATE] & 0x7FFFFFFF)) & 0xFFFFFFFF
			@mt[i] = @mt[(i+397) % INITIALSTATE] ^ (y >> 1)
			@mt[i] = @mt[i] ^ 0x9908b0df if y % 2 != 0 
			@index = 0 
		end 
	end 
end 

# Challenge 23 

def undoRightXOR(numToUnshift, shift)
	originalNum = numToUnshift
	endResult = numToUnshift
	
	i = 1
	while (i * shift <= 32)
		endResult = originalNum ^ (endResult >> shift)
		i += 1
	end 
	
	# We bitwise AND because we want the 32 Least Significant bits
	# Check: endResult.to_s(2).rjust(32, '0').chars.to_a.last(32).join 
	return endResult & 0xFFFFFFFF
end 

def undoLeftXOR(numToUnshift, shift, andMask = nil)
	originalNum = numToUnshift
	endResult = numToUnshift
	
	i = 1 
	while (i * shift <= 32)
		if andMask.nil?
			endResult = originalNum ^ (endResult << shift)
		else 
			endResult = originalNum ^ (endResult << shift) & andMask
		end 
		
		i += 1
	end 
	
	# We bitwise AND because we want the 32 Least Significant bits
	# .. Otherwise when we left shift sometimes ruby will expand past 32 bits. 
	# .. See: endResult.to_s(2).length 
	return endResult & 0xFFFFFFFF
end 

def untemper(y)
	y = undoRightXOR(y,18)
	y = undoLeftXOR(y, 15, 4022730752)
	y = undoLeftXOR(y, 7, 2636928640)
	y = undoRightXOR(y, 11)
	return (y & 0xFFFFFFFF)
end 

class MT19937CLONE < MT19937
	def setState(stateArray)
		@mt = stateArray
	end 
end 

# Challenge 24 
def makeKeyStream(length, seed)
	randoGen = MT19937.new(seed)
	finalOutput = Array.new
	length.times {
		finalOutput.push((randoGen.genRandNum % 256).chr)
	}
	return finalOutput
end 

def prngCTROperation(strtxt, seed)
	keyStream = makeKeyStream(strtxt.length, seed)
	return strtxt.chars.zip(keyStream).map { |x,y| (x.ord ^ y.ord).chr}.join 
end 

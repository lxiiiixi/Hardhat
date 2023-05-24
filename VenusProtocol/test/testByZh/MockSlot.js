const {
    time,
    getStorageAt,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MockSlot Upgrade Unit Test", function () {
    async function deployFixture() {
        const CustomMinERC1967Proxy = await ethers.getContractFactory("CustomMinERC1967Proxy");
        const MockSlot = await ethers.getContractFactory("MockSlot");
        const old_impl = await MockSlot.deploy();
        let instance = await CustomMinERC1967Proxy.deploy(old_impl.address);
        instance = MockSlot.attach(instance.address);
        const MockSlotNew = await ethers.getContractFactory("MockSlotNew");
        return {
            instance,MockSlotNew,CustomMinERC1967Proxy
        };
    }

    it("Upgrade should not change slot", async () => {
        let {instance,MockSlotNew,CustomMinERC1967Proxy} = await loadFixture(deployFixture);
        let param = {
            amount:600,
            lockedUntil:9876543210
        };
        await instance.setRequest(param,5);
        let request = await instance.getRequest(5);
        expect(request[0].amount).to.eq(param.amount);
        expect(request[0].lockedUntil).to.eq(param.lockedUntil);
        // calculate slot
        let start = ethers.utils.solidityKeccak256(["uint256","uint256"],[5,0]);
        let middle = ethers.utils.solidityKeccak256(["bytes32"],[start]);
        let next = ethers.BigNumber.from(middle).add(1);

        let info_0 = await getStorageAt(instance.address,middle);
        let amount  = ethers.BigNumber.from(info_0);
        let info_1 = await getStorageAt(instance.address,next);
        let lockedUntil = ethers.BigNumber.from(info_1);
        expect(amount).to.eq(param.amount);
        expect(lockedUntil).to.eq(param.lockedUntil);

        // upgrade
        let new_impl = await MockSlotNew.deploy();
        instance = CustomMinERC1967Proxy.attach(instance.address);
        await instance.updateTo(new_impl.address);
        instance = MockSlotNew.attach(instance.address);
        // check slot
        info_0 = await getStorageAt(instance.address,middle);
        amount  = ethers.BigNumber.from(info_0);
        info_1 = await getStorageAt(instance.address,next);
        lockedUntil = ethers.BigNumber.from(info_1);
        expect(amount).to.eq(param.amount);
        expect(lockedUntil).to.eq(param.lockedUntil);
        let info_2 = await getStorageAt(instance.address,next.add(1));
        expect(info_2).to.eq(ethers.constants.HashZero);

        // check state
        request = await instance.getRequest(5);
        expect(request[0].amount).to.eq(param.amount);
        expect(request[0].lockedUntil).to.eq(param.lockedUntil);
        expect(request[0].afterUpgrade).to.eq(0);

        // add new struct
        await instance.setRequest({
            amount:600,
            lockedUntil:9876543210,
            afterUpgrade:1
        },5);
        // check old slot
        info_0 = await getStorageAt(instance.address,middle);
        amount  = ethers.BigNumber.from(info_0);
        info_1 = await getStorageAt(instance.address,next);
        lockedUntil = ethers.BigNumber.from(info_1);
        expect(amount).to.eq(param.amount);
        expect(lockedUntil).to.eq(param.lockedUntil);
        // check new slot 
        info_0 = await getStorageAt(instance.address,next.add(1));
        amount  = ethers.BigNumber.from(info_0);
        info_1 = await getStorageAt(instance.address,next.add(2));
        lockedUntil = ethers.BigNumber.from("0x" + info_1.substring(34));
        let afterUpgrade = ethers.BigNumber.from(info_1.substring(0,34));
        expect(amount).to.eq(param.amount);
        expect(lockedUntil).to.eq(param.lockedUntil);
        expect(afterUpgrade).to.eq(1);

        // check state
        request = await instance.getRequest(5);
        expect(request[0].amount).to.eq(param.amount);
        expect(request[0].lockedUntil).to.eq(param.lockedUntil);
        expect(request[0].afterUpgrade).to.eq(0);

        expect(request[1].amount).to.eq(param.amount);
        expect(request[1].lockedUntil).to.eq(param.lockedUntil);
        expect(request[1].afterUpgrade).to.eq(1);

        let length_info = await getStorageAt(instance.address,start);
        let length = ethers.BigNumber.from(length_info);
        expect(length).to.eq(2);
    });
});
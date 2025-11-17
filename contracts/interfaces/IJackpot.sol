//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.28;

interface IJackpot {
    struct Ticket {
        uint8[] normals; //@note what is normals?
        uint8 bonusball; //@note what is this?
    }

    function buyTickets(
        Ticket[] memory _tickets,
        address _recipient,
        address[] memory _referrers,
        uint256[] memory _referralSplitBps,
        bytes32 _source //@note what do you mean by source?
    ) external returns (uint256[] memory ticketIds);

    function claimWinnings(uint256[] memory _userTicketIds) external;

    function ticketPrice() external view returns (uint256);
    function currentDrawingId() external view returns (uint256);
    //@note what is packed and unpacked ticket?
    function getUnpackedTicket(uint256 _drawingId, uint256 _packedTicket)
        external
        view
        returns (uint8[] memory, uint8);
}

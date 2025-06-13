// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title EventRSVP
 * @dev An event RSVP system where people can register for events
 */
contract EventRSVP {
    enum RSVPStatus {
        PENDING,
        CONFIRMED,
        CANCELLED,
        WAITLISTED
    }
    enum EventStatus {
        UPCOMING,
        ONGOING,
        COMPLETED,
        CANCELLED
    }

    struct Event {
        uint256 id;
        address organizer;
        string title;
        string description;
        string location;
        uint256 startTime;
        uint256 endTime;
        uint256 maxAttendees;
        uint256 confirmedCount;
        uint256 waitlistCount;
        bool requiresApproval;
        EventStatus status;
        uint256 createdAt;
    }

    struct RSVP {
        address attendee;
        uint256 eventId;
        RSVPStatus status;
        uint256 timestamp;
        string message; // Optional message from attendee
        bool checkedIn;
        uint256 checkedInAt;
    }

    // Storage
    Event[] public events;
    mapping(uint256 => mapping(address => RSVP)) public eventRSVPs;
    mapping(uint256 => address[]) public eventAttendees;
    mapping(uint256 => address[]) public eventWaitlist;
    mapping(address => uint256[]) public userEvents;
    mapping(address => uint256[]) public organizerEvents;

    uint256 public totalEvents;
    uint256 private nextEventId;

    // Configuration
    uint256 public constant MAX_EVENT_DURATION = 7 days;
    uint256 public constant MIN_ADVANCE_NOTICE = 1 hours;

    event EventCreated(
        uint256 indexed eventId, address indexed organizer, string title, uint256 startTime, uint256 maxAttendees
    );

    event RSVPSubmitted(uint256 indexed eventId, address indexed attendee, RSVPStatus status);

    event RSVPStatusChanged(
        uint256 indexed eventId, address indexed attendee, RSVPStatus oldStatus, RSVPStatus newStatus
    );

    event AttendeeCheckedIn(uint256 indexed eventId, address indexed attendee, uint256 timestamp);

    event EventStatusChanged(uint256 indexed eventId, EventStatus newStatus);

    modifier validEvent(uint256 _eventId) {
        require(_eventId < events.length, "Event does not exist");
        _;
    }

    modifier onlyOrganizer(uint256 _eventId) {
        require(events[_eventId].organizer == msg.sender, "Only organizer can perform this action");
        _;
    }

    /**
     * @dev Create a new event
     * @param _title Event title
     * @param _description Event description
     * @param _location Event location
     * @param _startTime Event start timestamp
     * @param _endTime Event end timestamp
     * @param _maxAttendees Maximum number of attendees (0 for unlimited)
     * @param _requiresApproval Whether RSVPs need organizer approval
     */
    function createEvent(
        string memory _title,
        string memory _description,
        string memory _location,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _maxAttendees,
        bool _requiresApproval
    ) external {
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(_startTime > block.timestamp + MIN_ADVANCE_NOTICE, "Event must be scheduled in advance");
        require(_endTime > _startTime, "End time must be after start time");
        require(_endTime - _startTime <= MAX_EVENT_DURATION, "Event duration too long");

        uint256 eventId = nextEventId;
        nextEventId++;

        Event memory newEvent = Event({
            id: eventId,
            organizer: msg.sender,
            title: _title,
            description: _description,
            location: _location,
            startTime: _startTime,
            endTime: _endTime,
            maxAttendees: _maxAttendees,
            confirmedCount: 0,
            waitlistCount: 0,
            requiresApproval: _requiresApproval,
            status: EventStatus.UPCOMING,
            createdAt: block.timestamp
        });

        events.push(newEvent);
        organizerEvents[msg.sender].push(eventId);
        totalEvents++;

        emit EventCreated(eventId, msg.sender, _title, _startTime, _maxAttendees);
    }

    /**
     * @dev RSVP to an event
     * @param _eventId Event ID
     * @param _message Optional message from attendee
     */
    function rsvp(uint256 _eventId, string memory _message) external validEvent(_eventId) {
        Event storage eventData = events[_eventId];
        require(eventData.status == EventStatus.UPCOMING, "Event is not accepting RSVPs");
        require(block.timestamp < eventData.startTime, "Event has already started");
        require(eventRSVPs[_eventId][msg.sender].attendee == address(0), "Already RSVPed");

        RSVPStatus initialStatus;

        // Determine initial status
        if (eventData.requiresApproval) {
            initialStatus = RSVPStatus.PENDING;
        } else if (eventData.maxAttendees == 0 || eventData.confirmedCount < eventData.maxAttendees) {
            initialStatus = RSVPStatus.CONFIRMED;
            eventData.confirmedCount++;
            eventAttendees[_eventId].push(msg.sender);
        } else {
            initialStatus = RSVPStatus.WAITLISTED;
            eventData.waitlistCount++;
            eventWaitlist[_eventId].push(msg.sender);
        }

        RSVP memory newRSVP = RSVP({
            attendee: msg.sender,
            eventId: _eventId,
            status: initialStatus,
            timestamp: block.timestamp,
            message: _message,
            checkedIn: false,
            checkedInAt: 0
        });

        eventRSVPs[_eventId][msg.sender] = newRSVP;
        userEvents[msg.sender].push(_eventId);

        emit RSVPSubmitted(_eventId, msg.sender, initialStatus);
    }

    /**
     * @dev Approve or reject a pending RSVP (organizer only)
     * @param _eventId Event ID
     * @param _attendee Attendee address
     * @param _approve True to approve, false to reject
     */
    function approveRSVP(uint256 _eventId, address _attendee, bool _approve)
        external
        validEvent(_eventId)
        onlyOrganizer(_eventId)
    {
        RSVP storage rsvp = eventRSVPs[_eventId][_attendee];
        require(rsvp.status == RSVPStatus.PENDING, "RSVP is not pending approval");

        Event storage eventData = events[_eventId];
        RSVPStatus oldStatus = rsvp.status;

        if (_approve) {
            if (eventData.maxAttendees == 0 || eventData.confirmedCount < eventData.maxAttendees) {
                rsvp.status = RSVPStatus.CONFIRMED;
                eventData.confirmedCount++;
                eventAttendees[_eventId].push(_attendee);
            } else {
                rsvp.status = RSVPStatus.WAITLISTED;
                eventData.waitlistCount++;
                eventWaitlist[_eventId].push(_attendee);
            }
        } else {
            rsvp.status = RSVPStatus.CANCELLED;
        }

        emit RSVPStatusChanged(_eventId, _attendee, oldStatus, rsvp.status);
    }

    /**
     * @dev Cancel your own RSVP
     * @param _eventId Event ID
     */
    function cancelRSVP(uint256 _eventId) external validEvent(_eventId) {
        RSVP storage rsvp = eventRSVPs[_eventId][msg.sender];
        require(rsvp.attendee == msg.sender, "No RSVP found");
        require(rsvp.status != RSVPStatus.CANCELLED, "RSVP already cancelled");

        Event storage eventData = events[_eventId];
        RSVPStatus oldStatus = rsvp.status;

        if (rsvp.status == RSVPStatus.CONFIRMED) {
            eventData.confirmedCount--;
            _removeFromArray(eventAttendees[_eventId], msg.sender);

            // Move someone from waitlist if space available
            if (eventWaitlist[_eventId].length > 0) {
                address waitlistUser = eventWaitlist[_eventId][0];
                _removeFromArray(eventWaitlist[_eventId], waitlistUser);
                eventAttendees[_eventId].push(waitlistUser);
                eventRSVPs[_eventId][waitlistUser].status = RSVPStatus.CONFIRMED;
                eventData.waitlistCount--;

                emit RSVPStatusChanged(_eventId, waitlistUser, RSVPStatus.WAITLISTED, RSVPStatus.CONFIRMED);
            }
        } else if (rsvp.status == RSVPStatus.WAITLISTED) {
            eventData.waitlistCount--;
            _removeFromArray(eventWaitlist[_eventId], msg.sender);
        }

        rsvp.status = RSVPStatus.CANCELLED;
        emit RSVPStatusChanged(_eventId, msg.sender, oldStatus, RSVPStatus.CANCELLED);
    }

    /**
     * @dev Check in an attendee (organizer only)
     * @param _eventId Event ID
     * @param _attendee Attendee address
     */
    function checkInAttendee(uint256 _eventId, address _attendee)
        external
        validEvent(_eventId)
        onlyOrganizer(_eventId)
    {
        RSVP storage rsvp = eventRSVPs[_eventId][_attendee];
        require(rsvp.status == RSVPStatus.CONFIRMED, "Attendee not confirmed");
        require(!rsvp.checkedIn, "Already checked in");

        Event storage eventData = events[_eventId];
        require(block.timestamp >= eventData.startTime, "Event has not started");
        require(block.timestamp <= eventData.endTime, "Event has ended");

        rsvp.checkedIn = true;
        rsvp.checkedInAt = block.timestamp;

        emit AttendeeCheckedIn(_eventId, _attendee, block.timestamp);
    }

    /**
     * @dev Update event status (organizer only)
     * @param _eventId Event ID
     * @param _status New status
     */
    function updateEventStatus(uint256 _eventId, EventStatus _status)
        external
        validEvent(_eventId)
        onlyOrganizer(_eventId)
    {
        Event storage eventData = events[_eventId];
        require(eventData.status != _status, "Status already set");

        eventData.status = _status;
        emit EventStatusChanged(_eventId, _status);
    }

    /**
     * @dev Get event details
     * @param _eventId Event ID
     * @return Event struct
     */
    function getEvent(uint256 _eventId) external view validEvent(_eventId) returns (Event memory) {
        return events[_eventId];
    }

    /**
     * @dev Get RSVP details for a user
     * @param _eventId Event ID
     * @param _attendee Attendee address
     * @return RSVP struct
     */
    function getRSVP(uint256 _eventId, address _attendee) external view returns (RSVP memory) {
        return eventRSVPs[_eventId][_attendee];
    }

    /**
     * @dev Get confirmed attendees for an event
     * @param _eventId Event ID
     * @return Array of attendee addresses
     */
    function getEventAttendees(uint256 _eventId) external view validEvent(_eventId) returns (address[] memory) {
        return eventAttendees[_eventId];
    }

    /**
     * @dev Get waitlisted users for an event
     * @param _eventId Event ID
     * @return Array of waitlisted addresses
     */
    function getEventWaitlist(uint256 _eventId) external view validEvent(_eventId) returns (address[] memory) {
        return eventWaitlist[_eventId];
    }

    /**
     * @dev Get events a user has RSVPed to
     * @param _user User address
     * @return Array of event IDs
     */
    function getUserEvents(address _user) external view returns (uint256[] memory) {
        return userEvents[_user];
    }

    /**
     * @dev Get events organized by a user
     * @param _organizer Organizer address
     * @return Array of event IDs
     */
    function getOrganizerEvents(address _organizer) external view returns (uint256[] memory) {
        return organizerEvents[_organizer];
    }

    /**
     * @dev Get upcoming events
     * @return Array of event IDs
     */
    function getUpcomingEvents() external view returns (uint256[] memory) {
        uint256 count = 0;

        // Count upcoming events
        for (uint256 i = 0; i < events.length; i++) {
            if (events[i].status == EventStatus.UPCOMING && events[i].startTime > block.timestamp) {
                count++;
            }
        }

        // Build array
        uint256[] memory upcomingEvents = new uint256[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < events.length; i++) {
            if (events[i].status == EventStatus.UPCOMING && events[i].startTime > block.timestamp) {
                upcomingEvents[index] = i;
                index++;
            }
        }

        return upcomingEvents;
    }

    /**
     * @dev Get total number of events
     * @return Total event count
     */
    function getTotalEvents() external view returns (uint256) {
        return totalEvents;
    }

    /**
     * @dev Helper function to remove address from array
     */
    function _removeFromArray(address[] storage array, address element) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                array[i] = array[array.length - 1];
                array.pop();
                break;
            }
        }
    }
}

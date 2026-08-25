-- Custom plate requests are only valid for vehicles that have already been registered.
-- Run this migration on existing installations.

UPDATE dmv_custom_plate_requests r
JOIN dmv_vehicle_ledger v ON v.id = r.vehicle_ledger_id
SET r.status = 'CANCELLED', r.rejection_reason = 'Legacy request cancelled: vehicle was not registered when the request was created.'
WHERE v.state = 'AWAITING_REGISTRATION'
  AND r.status IN ('PENDING','APPROVED');

DROP TRIGGER IF EXISTS st_dmv_custom_plate_registered_only;

DELIMITER $$
CREATE TRIGGER st_dmv_custom_plate_registered_only
BEFORE INSERT ON dmv_custom_plate_requests
FOR EACH ROW
BEGIN
    DECLARE vehicle_state VARCHAR(32);
    SELECT state INTO vehicle_state
    FROM dmv_vehicle_ledger
    WHERE id = NEW.vehicle_ledger_id
      AND buyer_citizenid = NEW.citizenid
    LIMIT 1;

    IF vehicle_state IS NULL OR vehicle_state NOT IN ('READY_FOR_PLATE','REGISTERED') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'DMV custom plate requests require a registered vehicle';
    END IF;
END$$
DELIMITER ;

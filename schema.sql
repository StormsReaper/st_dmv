CREATE TABLE IF NOT EXISTS dmv_locations (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  label VARCHAR(100) NOT NULL,
  x DECIMAL(10,4) NOT NULL,
  y DECIMAL(10,4) NOT NULL,
  z DECIMAL(10,4) NOT NULL,
  menu_x DECIMAL(10,4) NULL,
  menu_y DECIMAL(10,4) NULL,
  menu_z DECIMAL(10,4) NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dmv_settings (
  setting_key VARCHAR(64) NOT NULL,
  setting_value TEXT NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (setting_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dmv_drivers (
  citizenid VARCHAR(80) NOT NULL,
  name VARCHAR(120) NOT NULL,
  status ENUM('ACTIVE','SUSPENDED','REVOKED') NOT NULL DEFAULT 'ACTIVE',
  points INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dmv_licenses (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(80) NOT NULL,
  license_type ENUM('standard','cdl','taxi') NOT NULL,
  license_number VARCHAR(40) NOT NULL,
  status ENUM('ACTIVE','SUSPENDED','REVOKED','EXPIRED') NOT NULL DEFAULT 'ACTIVE',
  issued_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NULL,
  PRIMARY KEY (id), UNIQUE KEY uq_dmv_license_number (license_number), UNIQUE KEY uq_dmv_driver_license (citizenid, license_type), KEY idx_dmv_license_citizen (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dmv_violations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(80) NOT NULL,
  violation VARCHAR(160) NOT NULL,
  points INT NOT NULL DEFAULT 0,
  notes TEXT NULL,
  issued_by VARCHAR(100) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id), KEY idx_dmv_violation_citizen (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dmv_exam_questions (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  license_type ENUM('standard','cdl','taxi') NOT NULL DEFAULT 'standard',
  question TEXT NOT NULL,
  options JSON NOT NULL,
  correct_index TINYINT UNSIGNED NOT NULL,
  active TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (id), KEY idx_dmv_exam_type (license_type, active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dmv_exam_attempts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(80) NOT NULL,
  license_type VARCHAR(20) NOT NULL,
  score TINYINT UNSIGNED NOT NULL,
  passed TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id), KEY idx_dmv_attempt_citizen (citizenid, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dmv_vehicle_ledger (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  vin VARCHAR(64) NOT NULL,
  buyer_citizenid VARCHAR(80) NOT NULL,
  model VARCHAR(100) NULL,
  make VARCHAR(100) NULL,
  vehicle_name VARCHAR(160) NULL,
  sale_price DECIMAL(12,2) NOT NULL DEFAULT 0,
  temporary_plate VARCHAR(16) NOT NULL,
  assigned_plate VARCHAR(16) NULL,
  current_plate VARCHAR(16) NOT NULL,
  state ENUM('AWAITING_REGISTRATION','READY_FOR_PLATE','REGISTERED') NOT NULL DEFAULT 'AWAITING_REGISTRATION',
  registration_expires_at DATETIME NULL,
  registered_at TIMESTAMP NULL,
  plate_installed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id), UNIQUE KEY uq_dmv_vehicle_vin (vin), UNIQUE KEY uq_dmv_temp_plate (temporary_plate), UNIQUE KEY uq_dmv_assigned_plate (assigned_plate), KEY idx_dmv_vehicle_owner (buyer_citizenid, state), KEY idx_dmv_vehicle_current_plate (current_plate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dmv_custom_plate_requests (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  citizenid VARCHAR(80) NOT NULL,
  vehicle_ledger_id BIGINT UNSIGNED NOT NULL,
  requested_plate VARCHAR(16) NOT NULL,
  status ENUM('PENDING','APPROVED','REJECTED','PURCHASED','CANCELLED') NOT NULL DEFAULT 'PENDING',
  reviewed_by VARCHAR(80) NULL,
  reviewed_at DATETIME NULL,
  rejection_reason VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id), KEY idx_custom_plate_citizen (citizenid,status), KEY idx_custom_plate_vehicle (vehicle_ledger_id), CONSTRAINT fk_custom_plate_vehicle FOREIGN KEY (vehicle_ledger_id) REFERENCES dmv_vehicle_ledger(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO dmv_settings (setting_key, setting_value) VALUES
('registration_fee','350'),
('registration_coverage_days','365'),
('plate_format','OR-######'),
('custom_plate_enabled','1'),
('custom_plate_price','750')
ON DUPLICATE KEY UPDATE setting_key=VALUES(setting_key);

INSERT INTO dmv_exam_questions (license_type, question, options, correct_index) VALUES
('standard', 'What should you do at a red traffic signal?', '["Stop before the stop line","Speed up","Ignore it if no cars are present","Use hazard lights"]', 0),
('standard', 'Who has priority at a marked pedestrian crossing?', '["The pedestrian","The faster vehicle","The vehicle on the left","Nobody"]', 0),
('standard', 'What does a solid double yellow line generally indicate?', '["Do not cross to pass","Parking only","A bike lane","A railroad crossing"]', 0),
('cdl', 'Before operating a commercial vehicle, what should a driver perform?', '["A required pre-trip inspection","Only check fuel","Wash the vehicle","Nothing"]', 0),
('taxi', 'What is a taxi operator expected to maintain?', '["A valid taxi authorization and safe vehicle","Only a personal license","No records","A racing permit"]', 0)
ON DUPLICATE KEY UPDATE question = VALUES(question), options = VALUES(options), correct_index = VALUES(correct_index);

-- For existing installations run these migrations manually if the columns/tables already exist:
-- ALTER TABLE dmv_locations ADD COLUMN menu_x DECIMAL(10,4) NULL, ADD COLUMN menu_y DECIMAL(10,4) NULL, ADD COLUMN menu_z DECIMAL(10,4) NULL;
-- ALTER TABLE dmv_vehicle_ledger ADD COLUMN registration_expires_at DATETIME NULL;

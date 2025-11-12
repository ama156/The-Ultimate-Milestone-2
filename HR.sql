-- TODO: still not sure how to check for passwords
CREATE FUNCTION HRLoginValidation
(
    @employee_ID INT,
    @password VARCHAR(50)
)
RETURNS BIT
AS

BEGIN
    DECLARE @isValid BIT;

    IF EXISTS (
        SELECT 1
        FROM Employee
        WHERE employee_ID = @employee_ID
          AND password = @password
    )
        SET @isValid = 1;  -- Success
    ELSE
        SET @isValid = 0;  -- Failure

    RETURN @isValid;
END;

GO;

CREATE PROC HR_Approval_an_acc
    @request_ID INT,
    @HR_ID INT
AS
    
    DECLARE @emp_ID INT;
    DECLARE @type VARCHAR(20);
    DECLARE @num_days INT;

    SELECT @emp_ID = emp_ID, @type = type
    FROM
        (SELECT emp_ID, type = 'an'
        FROM Annual_Leave
        WHERE request_ID = @request_ID
        UNION
        SELECT emp_ID, type = 'acc'
        FROM Accidental_Leave
        WHERE request_ID = @request_ID)
    AS combined;

    SELECT @num_days = num_days
    FROM Leave
    WHERE request_ID = @request_ID;

    IF @type = 'an' BEGIN
        DECLARE @an_balance INT;

        SELECT @an_balance = annual_balance
        FROM Employee
        WHERE employee_ID = @emp_ID;

        -- TODO: I am creating a new approval here, not sure if I should instead remove the previous record or not
        IF @an_balance < @num_days BEGIN
            INSERT INTO Employee_Approve_Leave (emp1_ID, leave_ID, status)
            VALUES (@HR_ID, @request_ID, 'rejected');
        END ELSE BEGIN
            INSERT INTO Employee_Approve_Leave (emp1_ID, leave_ID, status)
            VALUES (@HR_ID, @request_ID, 'approved');
        END;
    END ELSE BEGIN
        DECLARE @acc_balance INT;

        SELECT @acc_balance = accidental_balance
        FROM Employee
        WHERE employee_ID = @emp_ID;

        -- TODO: I am creating a new approval here, not sure if I should instead remove the previous record or not
        IF @acc_balance < @num_days BEGIN
            INSERT INTO Employee_Approve_Leave (emp1_ID, leave_ID, status)
            VALUES (@HR_ID, @request_ID, 'rejected');
        END ELSE BEGIN
            INSERT INTO Employee_Approve_Leave (emp1_ID, leave_ID, status)
            VALUES (@HR_ID, @request_ID, 'approved');
        END;
    END;

GO;

CREATE PROC HR_approval_unpaid
    @request_ID INT,
    @HR_ID INT
AS

    DECLARE @emp_ID INT;
    DECLARE @duration INT;
    DECLARE @unpaid_leave_count INT;

    -- TODO: this is wrong, fix later
    SELECT @emp_ID = emp_ID, @duration = num_days
    FROM Leave_request
    WHERE request_ID = @request_ID;

    -- TODO: this is wrong, as you need to check the count per year, or otherwise use EXISTS
    SET @unpaid_leave_count = (SELECT COUNT(*)
                                FROM Unpaid_Leave
                                WHERE emp_ID = @emp_ID);

    IF @duration > 30 OR @unpaid_leave_count > 0 BEGIN
        INSERT INTO Employee_Approve_Leave (emp1_ID, leave_ID, status)
        VALUES (@HR_ID, @request_ID, 'rejected');
    END ELSE BEGIN
        INSERT INTO Employee_Approve_Leave (emp1_ID, leave_ID, status)
        VALUES (@HR_ID, @request_ID, 'approved');
    END;

GO;

CREATE PROC HR_approval_compensation
    @request_ID INT,
    @HR_ID INT
AS

    DECLARE @emp_ID INT;
    DECLARE @time_spent INT = 0;
    DECLARE @same_month BIT;

    -- TODO: this is wrong fix it
    SELECT @emp_ID = emp_ID
    FROM Leave_request
    WHERE request_ID = @request_ID;

    SELECT @time_spent = total_duration
    FROM Attendance
    WHERE date = (
        SELECT date_of_original_work_day
        FROM Compensation_Leave
        WHERE request_ID = @request_ID
    );

    IF 
        (SELECT MONTH(date_of_request)
        FROM Leave
        WHERE request_ID = @request_ID)
        =
        (SELECT MONTH(start_date)
        FROM Leave
        WHERE request_ID = @request_ID)
    BEGIN
        SET @same_month = 1;
    END ELSE BEGIN
        SET @same_month = 0;
    END;

    -- TODO: not sure if this is in hours or another format, need to check during testing as this assumes it is in hours
    IF @time_spent < 8 OR @same_month = 0 BEGIN
        INSERT INTO Employee_Approve_Leave (emp1_ID, leave_ID, status)
        VALUES (@HR_ID, @request_ID, 'rejected');
    END ELSE BEGIN
        INSERT INTO Employee_Approve_Leave (emp1_ID, leave_ID, status)
        VALUES (@HR_ID, @request_ID, 'approved');
    END;

GO;
-- TODO: complete rest of HR
-- yes I have so little respect for this thing that even the only things that I did for this file is not correct
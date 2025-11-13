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

    -- TODO: check if this is correct
    SELECT @emp_ID = emp_ID, @duration = num_days
    FROM
        Leave
        JOIN Unpaid_Leave ON Leave.request_ID = Unpaid_Leave.request_ID
    WHERE Leave.request_ID = @request_ID;

    -- TODO: check if this is correct
    SELECT @unpaid_leave_count = COUNT(*)
    FROM 
        Leave 
        JOIN Unpaid_Leave ON Leave.request_ID = Unpaid_Leave.request_ID
    WHERE Leave.status = 'approved' AND YEAR(Leave.request_date) = YEAR(GETDATE())
    GROUP BY YEAR(Leave.request_date);

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
    FROM 
        Leave
        JOIN Compensation_Leave ON Leave.request_ID = Compensation_Leave.request_ID
    WHERE Leave.request_ID = @request_ID;

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

CREATE PROC Deduction_hours
    @employee_ID INT
AS

    -- TODO: same as previous TODO
    DECLARE @attendance_ID INT = -1;
    SELECT TOP (1) 
        @attendance_ID = attendance_ID
    FROM Attendance
    WHERE 
        @emp_ID = employee_ID
        AND MONTH([date]) = MONTH(GETDATE())
        AND total_duration < 8
    ORDER BY [date];

    IF @attendance_ID <> -1 BEGIN

        -- TODO: IDK what the amount is, neither the status
        INSERT INTO Deduction (emp_ID, [date], type, attendance_ID)
        VALUES (@employee_ID, CAST(GETDATE() AS DATE), 'missing hours', @attendance_ID);

    END;

GO;

-- TODO: complete rest of HR
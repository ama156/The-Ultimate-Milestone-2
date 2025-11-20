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

    DECLARE @b BIT;

    IF EXISTS (
        SELECT *
        FROM Employee
        WHERE employee_ID = @employee_ID
          AND password = @password
    )
        SET @isValid = 1;
    ELSE
        SET @isValid = 0;

    RETURN @isValid;
END;

GO

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

GO

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

GO

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

GO

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

GO

CREATE FUNCTION Bonus_amount (@employee_ID INT)
    RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @salary DECIMAL(10,10),
            @overtime_factor DECIMAL(10,10),
            @rate_per_hour DECIMAL(10,10),
            @bonus DECIMAL(10,2);

    -- Get employee salary
    SELECT @salary = salary
    FROM Employee
    WHERE employee_ID = @employee_ID;

    SELECT TOP 1 @overtime_factor = percentage_overtime
    FROM Employee_Role ER
    JOIN Role R ON ER.role_name = R.role_name
    WHERE emp_ID = @employee_ID
    ORDER BY R.rank ASC;

    -- Rate per hour formula
    SET @rate_per_hour = (@salary / 22) / 8;

    -- Compute overtime across current month
    SELECT @bonus =
        SUM(
            @rate_per_hour *
            ((@overtime_factor *
              CASE 
                    WHEN total_duration > 8 THEN total_duration - 8
                    ELSE 0
              END) / 100.0)
        )
    FROM Attendance
    WHERE emp_ID = @employee_ID
      AND MONTH(date) = MONTH(GETDATE())
      AND YEAR(date) = YEAR(GETDATE());

    RETURN ISNULL(@bonus, 0);
END;

GO

CREATE PROCEDURE Add_Payroll
    @employee_ID INT,
    @from_date DATE,
    @to_date DATE
AS
BEGIN
    DECLARE @salary DECIMAL(10,10),
            @bonus DECIMAL(10,10),
            @deductions DECIMAL(10,10);

    -- Get salary
    SELECT @salary = salary
    FROM Employee
    WHERE employee_ID = @employee_ID;

    -- Get bonus via function
    SELECT @bonus = dbo.Bonus_amount(@employee_ID);

    -- Sum finalized deductions for the period
    SELECT @deductions = SUM(amount)
    FROM Deduction
    WHERE emp_ID = @employee_ID
        AND date BETWEEN @from_date AND @to_date
        AND status = 'pending';        -- not yet reflected in payroll

    SET @deductions = ISNULL(@deductions, 0);

    -- Insert payroll row
    INSERT INTO Payroll(payment_date, final_salary_amount,
                        from_date, to_date, comments,
                        bonus_amount, deductions_amount, emp_ID)
    VALUES(
        GETDATE(),
        @salary + @bonus - @deductions,
        @from_date,
        @to_date,
        NULL,
        @bonus,
        @deductions,
        @employee_ID
    );

    -- Finalize deductions now that they are reflected
    UPDATE Deduction
    SET status = 'finalized'
    WHERE emp_ID = @employee_ID
      AND date BETWEEN @from_date AND @to_date
      AND status = 'pending';
END;

GO

-- TODO: complete rest of HR
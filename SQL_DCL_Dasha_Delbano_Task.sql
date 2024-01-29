-- Create a new user with the username "rentaluser" and the password "rentalpassword". 
CREATE USER rentaluser WITH PASSWORD 'rentalpassword';

-- Give the user the ability to connect to the database but no other permissions.
GRANT CONNECT ON DATABASE dvdrental TO rentaluser;


-- Grant "rentaluser" SELECT permission for the "customer" table.
GRANT SELECT ON TABLE customer TO rentaluser;

-- Сheck to make sure this permission works correctly—write a SQL query to select all customers.
SET ROLE rentaluser;
SELECT * FROM customer;
RESET ROLE;

-- Create a new user group called "rental" and add "rentaluser" to the group. 
CREATE GROUP rental;
ALTER GROUP rental ADD USER rentaluser;
   

-- Grant INSERT and UPDATE on rental table to the rental group
GRANT INSERT, UPDATE ON rental TO GROUP rental;
GRANT USAGE, SELECT ON SEQUENCE rental_rental_id_seq TO GROUP rental;

-- Test INSERT and UPDATE as rentaluser
SET ROLE rentaluser;
INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
VALUES (CURRENT_DATE, 123, 456, CURRENT_DATE, 5, NOW());

UPDATE rental SET return_date = CURRENT_DATE WHERE rental_id = 1;
RESET ROLE;

-- Revoke INSERT permission from the rental group
REVOKE INSERT ON rental FROM GROUP rental;

-- Attempt to INSERT as rentaluser should fail
SET ROLE rentaluser;
INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
VALUES (CURRENT_DATE, 234, 567, CURRENT_DATE, 890, NOW());
RESET ROLE;

-- Create Personalized Role for a Customer
CREATE OR REPLACE FUNCTION create_customer_role()
RETURNS TEXT AS $$
DECLARE
  chosen_customer_id INT;
  customer_role_name TEXT;
BEGIN

-- Find a customer with rental and payment history
SELECT c.customer_id INTO chosen_customer_id
FROM customer c
JOIN rental r ON c.customer_id = r.customer_id
JOIN payment p ON c.customer_id = p.customer_id
GROUP BY c.customer_id
HAVING COUNT(DISTINCT r.rental_id) > 0 AND COUNT(DISTINCT p.payment_id) > 0
LIMIT 1;

-- Generate a unique role name
SELECT INTO customer_role_name
    'client_' || LOWER(c.first_name) || '_' || LOWER(c.last_name)
FROM customer c
WHERE c.customer_id = chosen_customer_id;

-- Create the role and grant permissions
EXECUTE FORMAT('CREATE ROLE %I', customer_role_name);
EXECUTE FORMAT('GRANT CONNECT ON DATABASE dvdrental1 TO %I', customer_role_name);
EXECUTE FORMAT('GRANT SELECT ON rental TO %I', customer_role_name);
EXECUTE FORMAT('GRANT SELECT ON payment TO %I', customer_role_name);

-- Enable row-level security and create policies
ALTER TABLE rental ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment ENABLE ROW LEVEL SECURITY;

EXECUTE FORMAT('CREATE POLICY access_own_data_rental ON rental USING (customer_id = %L) FOR SELECT TO %I', chosen_customer_id, customer_role_name);
EXECUTE FORMAT('CREATE POLICY access_own_data_payment ON payment USING (customer_id = %L) FOR SELECT TO %I', chosen_customer_id, customer_role_name);

-- Set and test the new role
SET ROLE TO customer_role_name;
RETURN customer_role_name;
END;
$$ LANGUAGE plpgsql;

-- Execute the function and test the role
SELECT create_customer_role();
SELECT * FROM rental;
SELECT * FROM payment;
RESET ROLE;

/* ============================================================================
   TPO_Comedores_FULL.sql
   TPO - Sistema de Gestión de Red de Comedores Comunitarios
   Versión completa e integrada — Proyecto Paralelo
   ----------------------------------------------------------------------------
   Ejecutar este único archivo en SQL Server Management Studio.
   Incluye: Base de datos, Tablas, Datos, Función, Triggers,
            Vistas y Procedimientos Almacenados.
   ============================================================================ */

/* ============================================================================
   SECCIÓN 0: CREACIÓN DE LA BASE DE DATOS
   ============================================================================ */
USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = N'TPO_Comedores_Completo')
    DROP DATABASE TPO_Comedores_Completo;
GO

CREATE DATABASE TPO_Comedores_Completo;
GO

USE TPO_Comedores_Completo;
GO

/* ============================================================================
   SECCIÓN 1: TABLAS INDEPENDIENTES (entidades fuertes, sin Foreign Keys)
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Comedor
-- Nodo central de la red. Prioridad manual (Alta/Media/Baja).
-- La cantidad de niños y ancianos se calcula desde Afiliado
-- usando FN_Calcular_Edad, no se almacena directamente.
-- ----------------------------------------------------------------------------
CREATE TABLE Comedor (
    ID_Comedor  INT IDENTITY(1,1)  NOT NULL,
    Nombre      VARCHAR(100)       NOT NULL,
    Direccion   VARCHAR(150)       NOT NULL,
    Zona        VARCHAR(50)        NOT NULL,
    Prioridad   VARCHAR(10)        NOT NULL,
    CONSTRAINT PK_Comedor           PRIMARY KEY (ID_Comedor),
    CONSTRAINT CK_Comedor_Prioridad CHECK (Prioridad IN ('Alta','Media','Baja'))
);
GO

-- ----------------------------------------------------------------------------
-- Almacen
-- Único almacén central de la red. Abastece comedores cuando
-- no hay excedente zonal disponible entre comedores hermanos.
-- ----------------------------------------------------------------------------
CREATE TABLE Almacen (
    ID_Almacen  INT IDENTITY(1,1)  NOT NULL,
    Nombre      VARCHAR(100)       NOT NULL,
    Direccion   VARCHAR(150)       NOT NULL,
    CONSTRAINT PK_Almacen PRIMARY KEY (ID_Almacen)
);
GO

-- ----------------------------------------------------------------------------
-- Voluntario
-- Persona que colabora en uno o más comedores (N:N via Ayuda).
-- ----------------------------------------------------------------------------
CREATE TABLE Voluntario (
    DNI              INT          NOT NULL,
    Nombre           VARCHAR(50)  NOT NULL,
    Apellido         VARCHAR(50)  NOT NULL,
    Direccion        VARCHAR(150) NOT NULL,
    Telefono         VARCHAR(20)  NULL,
    Email            VARCHAR(100) NULL,
    Fecha_Nacimiento DATE         NOT NULL,
    CONSTRAINT PK_Voluntario     PRIMARY KEY (DNI),
    CONSTRAINT CK_Voluntario_DNI CHECK (DNI > 0 AND DNI <= 99999999)
);
GO

-- ----------------------------------------------------------------------------
-- Donante
-- Persona que dona productos. Recibe avisos automáticos cuando
-- un comedor entra en estado de stock crítico.
-- ----------------------------------------------------------------------------
CREATE TABLE Donante (
    DNI              INT          NOT NULL,
    Nombre           VARCHAR(50)  NOT NULL,
    Apellido         VARCHAR(50)  NOT NULL,
    Direccion        VARCHAR(150) NOT NULL,
    Telefono         VARCHAR(20)  NULL,
    Email            VARCHAR(100) NULL,
    Fecha_Nacimiento DATE         NOT NULL,
    CONSTRAINT PK_Donante     PRIMARY KEY (DNI),
    CONSTRAINT CK_Donante_DNI CHECK (DNI > 0 AND DNI <= 99999999)
);
GO

/* ============================================================================
   SECCIÓN 2: TABLAS CON FOREIGN KEYS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Afiliado
-- Beneficiario único por DNI. Asignado a un único comedor (1:N).
-- La unicidad del DNI como PK impide que un mismo beneficiario
-- figure en dos comedores simultáneamente.
-- ----------------------------------------------------------------------------
CREATE TABLE Afiliado (
    DNI              INT          NOT NULL,
    Nombre           VARCHAR(50)  NOT NULL,
    Apellido         VARCHAR(50)  NOT NULL,
    Direccion        VARCHAR(150) NOT NULL,
    Telefono         VARCHAR(20)  NULL,
    Email            VARCHAR(100) NULL,
    Fecha_Nacimiento DATE         NOT NULL,
    ID_Comedor       INT          NOT NULL,
    CONSTRAINT PK_Afiliado          PRIMARY KEY (DNI),
    CONSTRAINT CK_Afiliado_DNI      CHECK (DNI > 0 AND DNI <= 99999999),
    CONSTRAINT FK_Afiliado_Comedor  FOREIGN KEY (ID_Comedor) REFERENCES Comedor (ID_Comedor)
);
GO

-- ----------------------------------------------------------------------------
-- Delivery
-- Movimiento de productos entre nodos de la red.
-- ORIGEN: puede ser un Almacen O un Comedor (nunca los dos).
-- DESTINO: siempre es un Comedor.
-- Esto soporta tanto Almacen→Comedor como Comedor→Comedor.
-- ----------------------------------------------------------------------------
CREATE TABLE Delivery (
    ID_Delivery        INT IDENTITY(1,1)  NOT NULL,
    Fecha              DATE               NOT NULL,
    ID_Comedor_Destino INT                NOT NULL,   -- destino siempre comedor
    ID_Almacen_Origen  INT                NULL,       -- origen: almacen (exclusivo)
    ID_Comedor_Origen  INT                NULL,       -- origen: comedor  (exclusivo)
    CONSTRAINT PK_Delivery             PRIMARY KEY (ID_Delivery),
    CONSTRAINT FK_Delivery_Destino     FOREIGN KEY (ID_Comedor_Destino) REFERENCES Comedor (ID_Comedor),
    CONSTRAINT FK_Delivery_AlmOrigen   FOREIGN KEY (ID_Almacen_Origen)  REFERENCES Almacen (ID_Almacen),
    CONSTRAINT FK_Delivery_ComOrigen   FOREIGN KEY (ID_Comedor_Origen)  REFERENCES Comedor (ID_Comedor),
    -- Exactamente uno de los dos orígenes debe tener valor
    CONSTRAINT CK_Delivery_Origen CHECK (
        (ID_Almacen_Origen IS NOT NULL AND ID_Comedor_Origen IS NULL) OR
        (ID_Almacen_Origen IS NULL     AND ID_Comedor_Origen IS NOT NULL)
    ),
    -- Un comedor no puede hacerse delivery a sí mismo
    CONSTRAINT CK_Delivery_NoAuto CHECK (
        ID_Comedor_Origen IS NULL OR ID_Comedor_Origen <> ID_Comedor_Destino
    )
);
GO

-- ----------------------------------------------------------------------------
-- Stock
-- Inventario lógico de un comedor (1:1).
-- Stock_Minimo: umbral para disparar alertas y logística automática.
-- El stock real se obtiene contando filas de Producto con este ID_Stock.
-- ----------------------------------------------------------------------------
CREATE TABLE Stock (
    ID_Stock     INT IDENTITY(1,1)  NOT NULL,
    ID_Comedor   INT                NOT NULL,
    Stock_Minimo INT                NOT NULL CONSTRAINT DF_Stock_Minimo DEFAULT 10,
    CONSTRAINT PK_Stock         PRIMARY KEY (ID_Stock),
    CONSTRAINT FK_Stock_Comedor FOREIGN KEY (ID_Comedor) REFERENCES Comedor (ID_Comedor),
    CONSTRAINT UQ_Stock_Comedor UNIQUE (ID_Comedor),       -- garantiza relación 1:1
    CONSTRAINT CK_Stock_Minimo  CHECK (Stock_Minimo >= 0)
);
GO

-- ----------------------------------------------------------------------------
-- Producto
-- Cada fila es una unidad física individual.
-- ID_Stock: indica en qué comedor está actualmente (nullable).
-- ID_Delivery: indica si está en tránsito en algún delivery (nullable).
-- Ambas pueden ser NULL si el producto está en el almacén
-- (registrado únicamente en la tabla Ingresa).
-- ----------------------------------------------------------------------------
CREATE TABLE Producto (
    ID_Producto       INT IDENTITY(1,1)  NOT NULL,
    Nombre            VARCHAR(100)       NOT NULL,
    Unidad_de_Medida  VARCHAR(20)        NOT NULL,
    Valor_de_Medida   DECIMAL(10,2)      NOT NULL,
    Fecha_Vencimiento DATE               NULL,
    ID_Stock          INT                NULL,
    ID_Delivery       INT                NULL,
    CONSTRAINT PK_Producto          PRIMARY KEY (ID_Producto),
    CONSTRAINT FK_Producto_Stock    FOREIGN KEY (ID_Stock)    REFERENCES Stock (ID_Stock),
    CONSTRAINT FK_Producto_Delivery FOREIGN KEY (ID_Delivery) REFERENCES Delivery (ID_Delivery),
    CONSTRAINT CK_Producto_Valor    CHECK (Valor_de_Medida > 0)
);
GO

/* ============================================================================
   SECCIÓN 3: TABLAS INTERMEDIAS N:N
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Ayuda  (Voluntario N:N Comedor)
-- Un voluntario puede ayudar en varios comedores y
-- un comedor puede tener varios voluntarios.
-- ----------------------------------------------------------------------------
CREATE TABLE Ayuda (
    DNI_Voluntario INT NOT NULL,
    ID_Comedor     INT NOT NULL,
    CONSTRAINT PK_Ayuda           PRIMARY KEY (DNI_Voluntario, ID_Comedor),
    CONSTRAINT FK_Ayuda_Voluntario FOREIGN KEY (DNI_Voluntario) REFERENCES Voluntario (DNI),
    CONSTRAINT FK_Ayuda_Comedor    FOREIGN KEY (ID_Comedor)     REFERENCES Comedor (ID_Comedor)
);
GO

-- ----------------------------------------------------------------------------
-- Ingresa  (Almacen N:N Producto con Fecha)
-- Registra el ingreso de un producto a un almacén.
-- Se mantiene para trazabilidad de entrada al sistema.
-- ----------------------------------------------------------------------------
CREATE TABLE Ingresa (
    ID_Almacen  INT  NOT NULL,
    ID_Producto INT  NOT NULL,
    Fecha       DATE NOT NULL,
    CONSTRAINT PK_Ingresa          PRIMARY KEY (ID_Almacen, ID_Producto, Fecha),
    CONSTRAINT FK_Ingresa_Almacen  FOREIGN KEY (ID_Almacen)  REFERENCES Almacen (ID_Almacen),
    CONSTRAINT FK_Ingresa_Producto FOREIGN KEY (ID_Producto) REFERENCES Producto (ID_Producto)
);
GO

-- ----------------------------------------------------------------------------
-- Dona  (Donante N:N Producto con Fecha)
-- Registra qué producto donó cada donante y cuándo.
-- Cada producto es una unidad individual, por eso no tiene Cantidad.
-- ----------------------------------------------------------------------------
CREATE TABLE Dona (
    ID_Producto INT  NOT NULL,
    DNI_Donante INT  NOT NULL,
    Fecha       DATE NOT NULL,
    CONSTRAINT PK_Dona          PRIMARY KEY (ID_Producto, DNI_Donante, Fecha),
    CONSTRAINT FK_Dona_Producto FOREIGN KEY (ID_Producto) REFERENCES Producto (ID_Producto),
    CONSTRAINT FK_Dona_Donante  FOREIGN KEY (DNI_Donante) REFERENCES Donante (DNI)
);
GO

/* ============================================================================
   SECCIÓN 4: TABLAS DE ALERTAS Y AVISOS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Alerta_Stock
-- Historial de alertas generadas automáticamente por triggers.
-- Tipos: 'Stock Bajo' cuando un comedor cae bajo su mínimo,
--        'Proximo Vencimiento' cuando un producto vence en ≤30 días.
-- ----------------------------------------------------------------------------
CREATE TABLE Alerta_Stock (
    ID_Alerta    INT IDENTITY(1,1)  NOT NULL,
    ID_Stock     INT                NOT NULL,
    ID_Producto  INT                NULL,      -- NULL en alertas de stock general
    Tipo_Alerta  VARCHAR(30)        NOT NULL,
    Fecha_Alerta DATETIME           NOT NULL CONSTRAINT DF_Alerta_Fecha    DEFAULT GETDATE(),
    Mensaje      VARCHAR(500)       NOT NULL,
    Resuelta     BIT                NOT NULL CONSTRAINT DF_Alerta_Resuelta DEFAULT 0,
    CONSTRAINT PK_Alerta_Stock          PRIMARY KEY (ID_Alerta),
    CONSTRAINT FK_Alerta_Stock_Stock    FOREIGN KEY (ID_Stock)    REFERENCES Stock (ID_Stock),
    CONSTRAINT FK_Alerta_Stock_Producto FOREIGN KEY (ID_Producto) REFERENCES Producto (ID_Producto),
    CONSTRAINT CK_Alerta_Tipo           CHECK (Tipo_Alerta IN ('Stock Bajo','Proximo Vencimiento'))
);
GO

-- ----------------------------------------------------------------------------
-- Aviso_Donante
-- Notificación generada para cada donante cuando hay stock crítico.
-- Permite a los donantes saber qué comedor necesita donaciones urgentes.
-- ----------------------------------------------------------------------------
CREATE TABLE Aviso_Donante (
    ID_Aviso    INT IDENTITY(1,1)  NOT NULL,
    ID_Alerta   INT                NOT NULL,
    DNI_Donante INT                NOT NULL,
    Fecha_Aviso DATETIME           NOT NULL CONSTRAINT DF_Aviso_Fecha DEFAULT GETDATE(),
    Leido       BIT                NOT NULL CONSTRAINT DF_Aviso_Leido DEFAULT 0,
    CONSTRAINT PK_Aviso_Donante     PRIMARY KEY (ID_Aviso),
    CONSTRAINT FK_Aviso_Alerta      FOREIGN KEY (ID_Alerta)   REFERENCES Alerta_Stock (ID_Alerta),
    CONSTRAINT FK_Aviso_Donante_DNI FOREIGN KEY (DNI_Donante) REFERENCES Donante (DNI)
);
GO

/* ============================================================================
   SECCIÓN 5: FUNCIÓN
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- FN_Calcular_Edad
-- Calcula la edad exacta en años a partir de una fecha de nacimiento.
-- Usada para clasificar afiliados como niños (<12) o ancianos (>60).
-- ----------------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.FN_Calcular_Edad (@Fecha_Nacimiento DATE)
RETURNS INT
AS
BEGIN
    DECLARE @Edad INT;
    SET @Edad = DATEDIFF(YEAR, @Fecha_Nacimiento, GETDATE())
        - CASE
            WHEN (MONTH(@Fecha_Nacimiento) > MONTH(GETDATE()))
              OR (MONTH(@Fecha_Nacimiento) = MONTH(GETDATE())
             AND  DAY(@Fecha_Nacimiento)   > DAY(GETDATE()))
            THEN 1 ELSE 0
          END;
    RETURN @Edad;
END
GO

/* ============================================================================
   SECCIÓN 6: DATOS DE PRUEBA
   ============================================================================ */

INSERT INTO Comedor (Nombre, Direccion, Zona, Prioridad) VALUES
    ('Comedor San Martin',   'Av. San Martin 1200',           'Centro', 'Alta'),
    ('Comedor La Boca',      'Brandsen 805',                  'Sur',    'Alta'),
    ('Comedor Belgrano',     'Monroe 2450',                   'Norte',  'Media'),
    ('Comedor Flores',       'Av. Rivadavia 7200',            'Oeste',  'Media'),
    ('Comedor Villa Devoto', 'Av. Lope de Vega 3200',         'Oeste',  'Baja'),
    ('Comedor Palermo',      'Honduras 5200',                 'Centro', 'Media'),
    ('Comedor Barracas',     'Suarez 1600',                   'Sur',    'Alta'),
    ('Comedor Caballito',    'Av. Directorio 1200',           'Centro', 'Media'),
    ('Comedor Nunez',        'Av. del Libertador 7800',       'Norte',  'Baja'),
    ('Comedor Mataderos',    'Av. Lisandro de la Torre 4800', 'Oeste',  'Alta');
GO

INSERT INTO Almacen (Nombre, Direccion) VALUES
    ('Almacen Central', 'Av. Corrientes 3500');
GO

INSERT INTO Voluntario (DNI, Nombre, Apellido, Direccion, Telefono, Email, Fecha_Nacimiento) VALUES
    (30123456, 'Lucia',     'Gomez',     'Av. Cabildo 1200',          '1155667788', 'lucia.gomez@gmail.com',      '1995-03-15'),
    (31234567, 'Martin',    'Perez',     'Thames 450',                '1144556677', 'martin.perez@gmail.com',     '1988-07-22'),
    (32345678, 'Carla',     'Rodriguez', 'Av. Santa Fe 2800',         '1133445566', 'carla.rodriguez@gmail.com',  '1992-11-08'),
    (33456789, 'Diego',     'Fernandez', 'Corrientes 5100',           '1122334455', 'diego.fernandez@gmail.com',  '1990-01-30'),
    (34567890, 'Sofia',     'Lopez',     'Av. Rivadavia 6400',        '1111223344', 'sofia.lopez@gmail.com',      '1998-05-12'),
    (35678901, 'Andres',    'Martinez',  'Honduras 4100',             '1199887766', 'andres.martinez@gmail.com',  '1985-09-25'),
    (36789012, 'Valentina', 'Sanchez',   'Av. Directorio 900',        '1188776655', 'valentina.sanchez@gmail.com','1993-12-03'),
    (37890123, 'Facundo',   'Romero',    'Brandsen 1200',             '1177665544', 'facundo.romero@gmail.com',   '1991-06-18'),
    (38901234, 'Camila',    'Torres',    'Monroe 3100',               '1166554433', 'camila.torres@gmail.com',    '1996-08-07'),
    (39012345, 'Nicolas',   'Diaz',      'Av. del Libertador 6200',   '1155443322', 'nicolas.diaz@gmail.com',     '1987-04-28');
GO

INSERT INTO Donante (DNI, Nombre, Apellido, Direccion, Telefono, Email, Fecha_Nacimiento) VALUES
    (20123456, 'Roberto',  'Alvarez', 'Av. Callao 800',          '1144332211', 'roberto.alvarez@gmail.com',  '1975-02-14'),
    (21234567, 'Elena',    'Molina',  'Scalabrini Ortiz 1200',   '1133221100', 'elena.molina@gmail.com',     '1980-10-05'),
    (22345678, 'Jorge',    'Castro',  'Av. Pueyrredon 900',      '1122110099', 'jorge.castro@gmail.com',     '1978-07-19'),
    (23456789, 'Patricia', 'Ruiz',    'Av. Las Heras 2200',      '1111009988', 'patricia.ruiz@gmail.com',    '1982-03-27'),
    (24567890, 'Hector',   'Vega',    'Av. San Juan 3500',       '1199008877', 'hector.vega@gmail.com',      '1970-11-11'),
    (25678901, 'Monica',   'Herrera', 'Av. Cramer 1800',         '1188997766', 'monica.herrera@gmail.com',   '1988-06-02'),
    (26789012, 'Oscar',    'Mendoza', 'Av. Boedo 1400',          '1177886655', 'oscar.mendoza@gmail.com',    '1973-09-16'),
    (27890123, 'Silvia',   'Navarro', 'Av. Entre Rios 1100',     '1166775544', 'silvia.navarro@gmail.com',   '1985-01-23'),
    (28901234, 'Ricardo',  'Silva',   'Av. Medrano 900',         '1155664433', 'ricardo.silva@gmail.com',    '1979-12-30'),
    (29012345, 'Gabriela', 'Morales', 'Av. Independencia 2800',  '1144553322', 'gabriela.morales@gmail.com', '1981-08-09');
GO

INSERT INTO Afiliado (DNI, Nombre, Apellido, Direccion, Telefono, Email, Fecha_Nacimiento, ID_Comedor) VALUES
    (40123456, 'Juan',    'Acosta',    'Av. San Martin 500',            '1155112233', 'juan.acosta@gmail.com',    '1960-04-10', 1),
    (41234567, 'Maria',   'Benitez',   'Brandsen 300',                  '1144223344', 'maria.benitez@gmail.com',  '1955-08-21', 2),
    (42345678, 'Pedro',   'Cabrera',   'Monroe 1800',                   '1135334455', 'pedro.cabrera@gmail.com',  '2015-12-05', 3),  -- niño
    (43456789, 'Ana',     'Dominguez', 'Av. Rivadavia 7100',            '1126445566', 'ana.dominguez@gmail.com',  '1958-02-18', 4),
    (44567890, 'Luis',    'Espinoza',  'Av. Lope de Vega 3100',         '1117556677', 'luis.espinoza@gmail.com',  '2016-06-30', 5),  -- niño
    (45678901, 'Rosa',    'Fuentes',   'Honduras 5000',                 '1108667788', 'rosa.fuentes@gmail.com',   '1962-09-14', 6),
    (46789012, 'Carlos',  'Gimenez',   'Suarez 1400',                   '1199778899', 'carlos.gimenez@gmail.com', '1950-11-25', 7),  -- anciano
    (47890123, 'Laura',   'Ibarra',    'Av. Directorio 1100',           '1180889900', 'laura.ibarra@gmail.com',   '1968-03-08', 8),
    (48901234, 'Miguel',  'Juarez',    'Av. del Libertador 7700',       '1171990011', 'miguel.juarez@gmail.com',  '1953-07-17', 9),  -- anciano
    (49012345, 'Claudia', 'Klein',     'Av. Lisandro de la Torre 4700', '1162001122', 'claudia.klein@gmail.com',  '1963-10-29', 10);
GO

-- Stock de cada comedor con su mínimo
-- Comedores Flores (4) y Villa Devoto (5) tienen mínimo bajo para pruebas de excedente
INSERT INTO Stock (ID_Comedor, Stock_Minimo) VALUES
    (1, 10), (2, 10), (3, 10),
    (4,  5),  -- Flores: mínimo bajo, tiene excedente para donar
    (5,  5),  -- Villa Devoto: mínimo bajo, puede quedar crítico
    (6, 10), (7, 10), (8, 10), (9, 10), (10, 10);
GO

-- Productos individuales en Comedor Flores (ID_Stock=4): 15 unidades → excedente
INSERT INTO Producto (Nombre, Unidad_de_Medida, Valor_de_Medida, Fecha_Vencimiento, ID_Stock, ID_Delivery) VALUES
    ('Arroz',   'Kg',     1.00, '2026-12-31', 4, NULL),
    ('Arroz',   'Kg',     1.00, '2026-12-31', 4, NULL),
    ('Arroz',   'Kg',     1.00, '2026-12-31', 4, NULL),
    ('Arroz',   'Kg',     1.00, '2026-12-31', 4, NULL),
    ('Arroz',   'Kg',     1.00, '2026-12-31', 4, NULL),
    ('Fideos',  'Kg',     1.20, '2026-10-15', 4, NULL),
    ('Fideos',  'Kg',     1.20, '2026-10-15', 4, NULL),
    ('Fideos',  'Kg',     1.20, '2026-10-15', 4, NULL),
    ('Fideos',  'Kg',     1.20, '2026-10-15', 4, NULL),
    ('Fideos',  'Kg',     1.20, '2026-10-15', 4, NULL),
    ('Aceite',  'Litro',  2.50, '2027-01-10', 4, NULL),
    ('Aceite',  'Litro',  2.50, '2027-01-10', 4, NULL),
    ('Aceite',  'Litro',  2.50, '2027-01-10', 4, NULL),
    ('Aceite',  'Litro',  2.50, '2027-01-10', 4, NULL),
    ('Aceite',  'Litro',  2.50, '2027-01-10', 4, NULL);
GO

-- Productos en Villa Devoto (ID_Stock=5): exactamente en su mínimo (5 unidades)
INSERT INTO Producto (Nombre, Unidad_de_Medida, Valor_de_Medida, Fecha_Vencimiento, ID_Stock, ID_Delivery) VALUES
    ('Pure de Tomate', 'Unidad', 0.80, '2026-05-20', 5, NULL),
    ('Pure de Tomate', 'Unidad', 0.80, '2026-05-20', 5, NULL),
    ('Pure de Tomate', 'Unidad', 0.80, '2026-05-20', 5, NULL),
    ('Pure de Tomate', 'Unidad', 0.80, '2026-05-20', 5, NULL),
    ('Pure de Tomate', 'Unidad', 0.80, '2026-05-20', 5, NULL);
GO

-- Productos en otros comedores para completar datos de prueba
INSERT INTO Producto (Nombre, Unidad_de_Medida, Valor_de_Medida, Fecha_Vencimiento, ID_Stock, ID_Delivery) VALUES
    ('Lentejas',       'Kg',     1.50, '2026-06-30', 1, NULL),
    ('Harina',         'Kg',     1.00, '2026-08-15', 2, NULL),
    ('Azucar',         'Kg',     1.20, '2026-09-01', 3, NULL),
    ('Leche en polvo', 'Kg',     2.00, '2026-07-20', 6, NULL),
    ('Atun en lata',   'Unidad', 1.50, '2027-03-10', 7, NULL),
    ('Polenta',        'Kg',     0.90, '2026-11-05', 8, NULL),
    ('Garbanzos',      'Kg',     1.30, '2026-10-22', 9, NULL),
    ('Sal',            'Kg',     0.50, '2027-06-30', 10, NULL),
    -- Producto próximo a vencer para probar trigger de vencimiento
    ('Yogur',          'Unidad', 0.60, '2026-07-10', 1, NULL),
    ('Manteca',        'Kg',     3.00, '2026-07-15', 2, NULL);
GO

INSERT INTO Ayuda (DNI_Voluntario, ID_Comedor) VALUES
    (30123456, 1), (31234567, 2), (32345678, 3),
    (33456789, 4), (34567890, 5), (35678901, 6),
    (36789012, 7), (37890123, 8), (38901234, 9),
    (39012345, 10);
GO

-- Deliveries históricos: mezcla de almacén→comedor y comedor→comedor
INSERT INTO Delivery (Fecha, ID_Comedor_Destino, ID_Almacen_Origen, ID_Comedor_Origen) VALUES
    ('2026-01-10', 1,  1, NULL),   -- Almacen → San Martin
    ('2026-01-15', 2,  1, NULL),   -- Almacen → La Boca
    ('2026-02-01', 3,  1, NULL),   -- Almacen → Belgrano
    ('2026-02-10', 5,  1, NULL),   -- Almacen → Villa Devoto
    ('2026-03-05', 6,  1, NULL),   -- Almacen → Palermo
    ('2026-03-12', 7,  1, NULL),   -- Almacen → Barracas
    ('2026-04-01', 9,  NULL, 3),   -- Belgrano → Nunez (comedor a comedor)
    ('2026-04-15', 10, NULL, 4),   -- Flores   → Mataderos (comedor a comedor)
    ('2026-05-01', 8,  NULL, 1),   -- San Martin → Caballito (comedor a comedor)
    ('2026-05-20', 2,  NULL, 7);   -- Barracas → La Boca (comedor a comedor)
GO

INSERT INTO Ingresa (ID_Almacen, ID_Producto, Fecha) VALUES
    (1,  1, '2026-01-05'), (1,  2, '2026-01-06'),
    (1,  3, '2026-01-07'), (1,  6, '2026-01-08'),
    (1,  7, '2026-01-09'), (1,  8, '2026-01-10'),
    (1, 11, '2026-01-11'), (1, 16, '2026-01-12'),
    (1, 21, '2026-01-13'), (1, 22, '2026-01-14');
GO

INSERT INTO Dona (ID_Producto, DNI_Donante, Fecha) VALUES
    ( 4, 20123456, '2026-01-07'), ( 5, 21234567, '2026-01-09'),
    ( 9, 22345678, '2026-01-11'), (10, 23456789, '2026-01-13'),
    (12, 24567890, '2026-01-15'), (14, 25678901, '2026-01-17'),
    (17, 26789012, '2026-01-19'), (18, 27890123, '2026-01-21'),
    (19, 28901234, '2026-01-23'), (20, 29012345, '2026-01-25');
GO

/* ============================================================================
   SECCIÓN 7: TRIGGERS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- TRIGGER 1: TR_Vencimiento_Proximo
-- AFTER INSERT en Producto.
-- Si un producto nuevo tiene fecha de vencimiento dentro de 30 días,
-- registra automáticamente una alerta en Alerta_Stock.
-- ----------------------------------------------------------------------------
CREATE OR ALTER TRIGGER TR_Vencimiento_Proximo
ON Producto
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Alerta_Stock (ID_Stock, ID_Producto, Tipo_Alerta, Mensaje)
    SELECT
        i.ID_Stock,
        i.ID_Producto,
        'Proximo Vencimiento',
        'ALERTA: El producto "' + i.Nombre + '" (ID: ' + CAST(i.ID_Producto AS VARCHAR) +
        ') vence el ' + CONVERT(VARCHAR, i.Fecha_Vencimiento, 103) +
        '. Quedan ' + CAST(DATEDIFF(DAY, CAST(GETDATE() AS DATE), i.Fecha_Vencimiento) AS VARCHAR) +
        ' dia/s para su vencimiento.'
    FROM inserted i
    WHERE i.Fecha_Vencimiento IS NOT NULL
      AND i.ID_Stock IS NOT NULL
      AND i.Fecha_Vencimiento <= DATEADD(DAY, 30, CAST(GETDATE() AS DATE));
END;
GO

-- ----------------------------------------------------------------------------
-- TRIGGER 2: TR_Aviso_Donantes_Stock_Bajo
-- AFTER INSERT en Alerta_Stock.
-- Cuando se registra una alerta de tipo 'Stock Bajo',
-- genera un aviso para TODOS los donantes registrados.
-- ----------------------------------------------------------------------------
CREATE OR ALTER TRIGGER TR_Aviso_Donantes_Stock_Bajo
ON Alerta_Stock
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted WHERE Tipo_Alerta = 'Stock Bajo')
        RETURN;

    INSERT INTO Aviso_Donante (ID_Alerta, DNI_Donante)
    SELECT i.ID_Alerta, d.DNI
    FROM inserted i
    CROSS JOIN Donante d
    WHERE i.Tipo_Alerta = 'Stock Bajo';
END;
GO

-- ----------------------------------------------------------------------------
-- TRIGGER 3: TR_Control_Stock_Bajas
-- AFTER DELETE en Producto.
-- Cuando se eliminan productos de un comedor, verifica si el stock
-- cayó por debajo del mínimo. Si es así:
--   1. Registra alerta en Alerta_Stock (dispara TR_Aviso_Donantes)
--   2. Ejecuta usp_Logistica_AuxilioAutomatico para resolver el faltante
-- ----------------------------------------------------------------------------
CREATE OR ALTER TRIGGER TR_Control_Stock_Bajas
ON Producto
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ID_Stock_Afectado   INT;
    DECLARE @ID_Comedor_Afectado INT;
    DECLARE @Stock_Actual        INT;
    DECLARE @Stock_Minimo        INT;
    DECLARE @Nombre_Comedor      VARCHAR(100);

    DECLARE cur_Bajas CURSOR LOCAL FAST_FORWARD FOR
        SELECT del.ID_Stock, s.ID_Comedor, s.Stock_Minimo
        FROM deleted del
        INNER JOIN Stock s ON del.ID_Stock = s.ID_Stock
        WHERE del.ID_Stock IS NOT NULL
        GROUP BY del.ID_Stock, s.ID_Comedor, s.Stock_Minimo;

    OPEN cur_Bajas;
    FETCH NEXT FROM cur_Bajas INTO @ID_Stock_Afectado, @ID_Comedor_Afectado, @Stock_Minimo;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SELECT @Stock_Actual   = COUNT(*) FROM Producto WHERE ID_Stock = @ID_Stock_Afectado;
        SELECT @Nombre_Comedor = Nombre   FROM Comedor  WHERE ID_Comedor = @ID_Comedor_Afectado;

        IF @Stock_Actual < @Stock_Minimo
        BEGIN
            -- Registrar alerta (esto dispara TR_Aviso_Donantes_Stock_Bajo)
            INSERT INTO Alerta_Stock (ID_Stock, ID_Producto, Tipo_Alerta, Mensaje)
            VALUES (
                @ID_Stock_Afectado,
                NULL,
                'Stock Bajo',
                'ALERTA CRÍTICA: El comedor "' + @Nombre_Comedor +
                '" tiene ' + CAST(@Stock_Actual AS VARCHAR) +
                ' unidades, por debajo del mínimo de ' + CAST(@Stock_Minimo AS VARCHAR) + '.' +
                ' Se activa logística automática de auxilio.'
            );

            -- Activar logística automática
            EXEC usp_Logistica_AuxilioAutomatico
                @ID_Comedor_Destino = @ID_Comedor_Afectado,
                @Stock_Actual       = @Stock_Actual,
                @Stock_Minimo       = @Stock_Minimo;
        END

        FETCH NEXT FROM cur_Bajas INTO @ID_Stock_Afectado, @ID_Comedor_Afectado, @Stock_Minimo;
    END

    CLOSE cur_Bajas;
    DEALLOCATE cur_Bajas;
END;
GO

/* ============================================================================
   SECCIÓN 8: VISTAS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- Vista 1: VW_Stock_Actual_Por_Comedor
-- Muestra el estado actual del inventario de cada comedor:
-- stock real (conteo de productos), productos próximos a vencer
-- y estado general (CRÍTICO / BAJO / NORMAL).
-- Útil para monitoreo operativo de la red.
-- ----------------------------------------------------------------------------
CREATE OR ALTER VIEW VW_Stock_Actual_Por_Comedor
AS
SELECT
    c.ID_Comedor,
    c.Nombre                                                AS Comedor,
    c.Zona,
    c.Prioridad,
    s.ID_Stock,
    s.Stock_Minimo,
    COUNT(p.ID_Producto)                                    AS Stock_Actual,
    SUM(CASE
            WHEN p.Fecha_Vencimiento IS NOT NULL
             AND p.Fecha_Vencimiento <= DATEADD(DAY, 30, CAST(GETDATE() AS DATE))
            THEN 1 ELSE 0
        END)                                                AS Proximos_A_Vencer,
    -- Cantidad de niños afiliados (menores de 12)
    (SELECT COUNT(*) FROM Afiliado a
     WHERE a.ID_Comedor = c.ID_Comedor
       AND dbo.FN_Calcular_Edad(a.Fecha_Nacimiento) < 12)  AS Cant_Ninos,
    -- Cantidad de ancianos afiliados (mayores de 60)
    (SELECT COUNT(*) FROM Afiliado a
     WHERE a.ID_Comedor = c.ID_Comedor
       AND dbo.FN_Calcular_Edad(a.Fecha_Nacimiento) > 60)  AS Cant_Ancianos,
    CASE
        WHEN COUNT(p.ID_Producto) < s.Stock_Minimo         THEN 'CRÍTICO'
        WHEN COUNT(p.ID_Producto) < s.Stock_Minimo * 1.5   THEN 'BAJO'
        ELSE 'NORMAL'
    END                                                     AS Estado_Stock
FROM Comedor c
INNER JOIN Stock   s ON c.ID_Comedor = s.ID_Comedor
LEFT  JOIN Producto p ON s.ID_Stock  = p.ID_Stock
GROUP BY c.ID_Comedor, c.Nombre, c.Zona, c.Prioridad, s.ID_Stock, s.Stock_Minimo;
GO

-- ----------------------------------------------------------------------------
-- Vista 2: VW_Ranking_Necesidad_Comedores
-- Ordena los comedores con faltante real de mayor a menor urgencia.
-- El Índice de Urgencia combina el déficit de stock con la prioridad
-- del comedor (Alta=3, Media=2, Baja=1).
-- Pensada para que los donantes vean dónde donar primero.
-- Consultar con: SELECT * FROM VW_Ranking_Necesidad_Comedores ORDER BY Indice_Urgencia DESC
-- ----------------------------------------------------------------------------
CREATE OR ALTER VIEW VW_Ranking_Necesidad_Comedores
AS
SELECT
    c.ID_Comedor,
    c.Nombre                                        AS Comedor,
    c.Zona,
    c.Prioridad,
    s.Stock_Minimo,
    COUNT(p.ID_Producto)                            AS Stock_Actual,
    s.Stock_Minimo - COUNT(p.ID_Producto)           AS Unidades_Faltantes,
    (s.Stock_Minimo - COUNT(p.ID_Producto)) *
        CASE c.Prioridad
            WHEN 'Alta'  THEN 3
            WHEN 'Media' THEN 2
            WHEN 'Baja'  THEN 1
            ELSE 1
        END                                         AS Indice_Urgencia
FROM Comedor c
INNER JOIN Stock    s ON c.ID_Comedor = s.ID_Comedor
LEFT  JOIN Producto p ON s.ID_Stock   = p.ID_Stock
GROUP BY c.ID_Comedor, c.Nombre, c.Zona, c.Prioridad, s.Stock_Minimo
HAVING (s.Stock_Minimo - COUNT(p.ID_Producto)) > 0;
GO

/* ============================================================================
   SECCIÓN 9: PROCEDIMIENTOS ALMACENADOS
   ============================================================================ */

-- ----------------------------------------------------------------------------
-- usp_Comedor_Insertar
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Comedor_Insertar
    @Nombre    VARCHAR(100),
    @Direccion VARCHAR(150),
    @Zona      VARCHAR(50),
    @Prioridad VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO Comedor (Nombre, Direccion, Zona, Prioridad)
    VALUES (@Nombre, @Direccion, @Zona, @Prioridad);
    SELECT SCOPE_IDENTITY() AS ID_Comedor_Generado;
END
GO

-- ----------------------------------------------------------------------------
-- usp_Comedor_Actualizar
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Comedor_Actualizar
    @ID_Comedor INT,
    @Nombre     VARCHAR(100),
    @Direccion  VARCHAR(150),
    @Zona       VARCHAR(50),
    @Prioridad  VARCHAR(10)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM Comedor WHERE ID_Comedor = @ID_Comedor)
    BEGIN
        RAISERROR('No existe un Comedor con ID_Comedor = %d.', 16, 1, @ID_Comedor);
        RETURN;
    END
    UPDATE Comedor
    SET Nombre = @Nombre, Direccion = @Direccion, Zona = @Zona, Prioridad = @Prioridad
    WHERE ID_Comedor = @ID_Comedor;
END
GO

-- ----------------------------------------------------------------------------
-- usp_Afiliado_Consultar
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Afiliado_Consultar
    @ID_Comedor INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        a.DNI, a.Nombre, a.Apellido, a.Fecha_Nacimiento,
        dbo.FN_Calcular_Edad(a.Fecha_Nacimiento) AS Edad,
        a.ID_Comedor,
        c.Nombre AS Nombre_Comedor
    FROM Afiliado a
    INNER JOIN Comedor c ON c.ID_Comedor = a.ID_Comedor
    WHERE @ID_Comedor IS NULL OR a.ID_Comedor = @ID_Comedor
    ORDER BY a.Apellido, a.Nombre;
END
GO

-- ----------------------------------------------------------------------------
-- usp_Afiliado_Eliminar
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Afiliado_Eliminar
    @DNI INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM Afiliado WHERE DNI = @DNI)
    BEGIN
        RAISERROR('No existe un Afiliado con DNI = %d.', 16, 1, @DNI);
        RETURN;
    END
    DELETE FROM Afiliado WHERE DNI = @DNI;
END
GO

-- ----------------------------------------------------------------------------
-- usp_Voluntario_Insertar
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Voluntario_Insertar
    @DNI              INT,
    @Nombre           VARCHAR(50),
    @Apellido         VARCHAR(50),
    @Direccion        VARCHAR(150),
    @Telefono         VARCHAR(20)  = NULL,
    @Email            VARCHAR(100) = NULL,
    @Fecha_Nacimiento DATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM Voluntario WHERE DNI = @DNI)
    BEGIN
        RAISERROR('Ya existe un Voluntario con DNI = %d.', 16, 1, @DNI);
        RETURN;
    END
    INSERT INTO Voluntario (DNI, Nombre, Apellido, Direccion, Telefono, Email, Fecha_Nacimiento)
    VALUES (@DNI, @Nombre, @Apellido, @Direccion, @Telefono, @Email, @Fecha_Nacimiento);
END
GO

-- ----------------------------------------------------------------------------
-- usp_Voluntario_Eliminar
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Voluntario_Eliminar
    @DNI INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM Voluntario WHERE DNI = @DNI)
    BEGIN
        RAISERROR('No existe un Voluntario con DNI = %d.', 16, 1, @DNI);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM Ayuda WHERE DNI_Voluntario = @DNI)
    BEGIN
        RAISERROR('No se puede eliminar: el Voluntario tiene comedores asignados en Ayuda.', 16, 1);
        RETURN;
    END
    DELETE FROM Voluntario WHERE DNI = @DNI;
END
GO

-- ----------------------------------------------------------------------------
-- usp_Producto_Actualizar
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Producto_Actualizar
    @ID_Producto       INT,
    @Nombre            VARCHAR(100),
    @Unidad_de_Medida  VARCHAR(20),
    @Valor_de_Medida   DECIMAL(10,2),
    @Fecha_Vencimiento DATE = NULL,
    @ID_Stock          INT  = NULL,
    @ID_Delivery       INT  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM Producto WHERE ID_Producto = @ID_Producto)
    BEGIN
        RAISERROR('No existe un Producto con ID_Producto = %d.', 16, 1, @ID_Producto);
        RETURN;
    END
    UPDATE Producto
    SET Nombre           = @Nombre,
        Unidad_de_Medida = @Unidad_de_Medida,
        Valor_de_Medida  = @Valor_de_Medida,
        Fecha_Vencimiento= @Fecha_Vencimiento,
        ID_Stock         = @ID_Stock,
        ID_Delivery      = @ID_Delivery
    WHERE ID_Producto = @ID_Producto;
END
GO

-- ----------------------------------------------------------------------------
-- usp_Producto_ConsultarProximosAVencer
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Producto_ConsultarProximosAVencer
    @Dias_Limite INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        p.ID_Producto, p.Nombre, p.Unidad_de_Medida,
        p.Valor_de_Medida, p.Fecha_Vencimiento,
        c.Nombre AS Comedor_Actual,
        DATEDIFF(DAY, CAST(GETDATE() AS DATE), p.Fecha_Vencimiento) AS Dias_Restantes
    FROM Producto p
    LEFT JOIN Stock   s ON p.ID_Stock   = s.ID_Stock
    LEFT JOIN Comedor c ON s.ID_Comedor = c.ID_Comedor
    WHERE p.Fecha_Vencimiento IS NOT NULL
      AND p.Fecha_Vencimiento <= DATEADD(DAY, @Dias_Limite, CAST(GETDATE() AS DATE))
    ORDER BY p.Fecha_Vencimiento ASC;
END
GO

-- ----------------------------------------------------------------------------
-- usp_Delivery_Insertar
-- Versión extendida: acepta origen flexible (almacén O comedor).
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Delivery_Insertar
    @Fecha              DATE,
    @ID_Comedor_Destino INT,
    @ID_Almacen_Origen  INT = NULL,
    @ID_Comedor_Origen  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @ID_Almacen_Origen IS NULL AND @ID_Comedor_Origen IS NULL
    BEGIN
        RAISERROR('Debe especificar al menos un origen: ID_Almacen_Origen o ID_Comedor_Origen.', 16, 1);
        RETURN;
    END

    IF @ID_Almacen_Origen IS NOT NULL AND @ID_Comedor_Origen IS NOT NULL
    BEGIN
        RAISERROR('Solo puede especificar un origen: ID_Almacen_Origen O ID_Comedor_Origen, no ambos.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Comedor WHERE ID_Comedor = @ID_Comedor_Destino)
    BEGIN
        RAISERROR('No existe un Comedor destino con ID_Comedor = %d.', 16, 1, @ID_Comedor_Destino);
        RETURN;
    END

    INSERT INTO Delivery (Fecha, ID_Comedor_Destino, ID_Almacen_Origen, ID_Comedor_Origen)
    VALUES (@Fecha, @ID_Comedor_Destino, @ID_Almacen_Origen, @ID_Comedor_Origen);

    SELECT SCOPE_IDENTITY() AS ID_Delivery_Generado;
END
GO

-- ----------------------------------------------------------------------------
-- usp_Delivery_ConsultarPorComedor
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Delivery_ConsultarPorComedor
    @ID_Comedor INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        d.ID_Delivery,
        d.Fecha,
        c_dest.Nombre                                           AS Comedor_Destino,
        COALESCE(al.Nombre, 'N/A')                             AS Almacen_Origen,
        COALESCE(c_orig.Nombre, 'N/A')                         AS Comedor_Origen,
        CASE
            WHEN d.ID_Almacen_Origen IS NOT NULL THEN 'Almacen → Comedor'
            ELSE 'Comedor → Comedor'
        END                                                     AS Tipo_Delivery
    FROM Delivery d
    INNER JOIN Comedor c_dest ON d.ID_Comedor_Destino = c_dest.ID_Comedor
    LEFT  JOIN Almacen al     ON d.ID_Almacen_Origen  = al.ID_Almacen
    LEFT  JOIN Comedor c_orig ON d.ID_Comedor_Origen  = c_orig.ID_Comedor
    WHERE d.ID_Comedor_Destino = @ID_Comedor
       OR d.ID_Comedor_Origen  = @ID_Comedor
    ORDER BY d.Fecha DESC;
END
GO

-- ----------------------------------------------------------------------------
-- usp_Logistica_AuxilioAutomatico  ← PROCEDIMIENTO CORE
-- Llamado por TR_Control_Stock_Bajas cuando un comedor queda bajo mínimo.
-- Lógica:
--   1. Busca en la misma zona un comedor con más del doble de su mínimo
--   2. Si lo encuentra → Delivery comedor→comedor, mueve los productos
--      más próximos a vencer primero (FIFO por vencimiento)
--   3. Si no → Delivery almacén→comedor como fallback
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Logistica_AuxilioAutomatico
    @ID_Comedor_Destino INT,
    @Stock_Actual       INT,
    @Stock_Minimo       INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Cantidad_A_Pedir   INT;
    DECLARE @Zona               VARCHAR(50);
    DECLARE @ID_Comedor_Origen  INT;
    DECLARE @ID_Stock_Origen    INT;
    DECLARE @ID_Stock_Destino   INT;
    DECLARE @Nuevo_Delivery_ID  INT;
    DECLARE @ID_Almacen_Central INT;

    SET @Cantidad_A_Pedir = (@Stock_Minimo - @Stock_Actual) + 5;

    SELECT @Zona             = Zona       FROM Comedor WHERE ID_Comedor = @ID_Comedor_Destino;
    SELECT @ID_Stock_Destino = ID_Stock   FROM Stock   WHERE ID_Comedor = @ID_Comedor_Destino;
    SELECT TOP 1 @ID_Almacen_Central = ID_Almacen FROM Almacen ORDER BY ID_Almacen;

    -- Buscar comedor hermano en la misma zona con excedente real (> doble de su mínimo)
    SELECT TOP 1
        @ID_Comedor_Origen = c.ID_Comedor,
        @ID_Stock_Origen   = s.ID_Stock
    FROM Comedor c
    INNER JOIN Stock s ON c.ID_Comedor = s.ID_Comedor
    WHERE c.Zona       = @Zona
      AND c.ID_Comedor <> @ID_Comedor_Destino
      AND (SELECT COUNT(*) FROM Producto WHERE ID_Stock = s.ID_Stock) > (s.Stock_Minimo * 2)
    ORDER BY (SELECT COUNT(*) FROM Producto WHERE ID_Stock = s.ID_Stock) DESC;

    IF @ID_Comedor_Origen IS NOT NULL
    BEGIN
        -- CASO A: Transferencia comedor → comedor (red solidaria)
        INSERT INTO Delivery (Fecha, ID_Comedor_Destino, ID_Almacen_Origen, ID_Comedor_Origen)
        VALUES (CAST(GETDATE() AS DATE), @ID_Comedor_Destino, NULL, @ID_Comedor_Origen);

        SET @Nuevo_Delivery_ID = SCOPE_IDENTITY();

        -- Mover los N productos más próximos a vencer del comedor origen al destino
        UPDATE Producto
        SET ID_Stock   = @ID_Stock_Destino,
            ID_Delivery = @Nuevo_Delivery_ID
        WHERE ID_Producto IN (
            SELECT TOP (@Cantidad_A_Pedir) ID_Producto
            FROM Producto
            WHERE ID_Stock = @ID_Stock_Origen
            ORDER BY Fecha_Vencimiento ASC, ID_Producto ASC
        );

        PRINT 'LOGÍSTICA: Auxilio zonal exitoso. Se transfirieron '
            + CAST(@Cantidad_A_Pedir AS VARCHAR) + ' unidades desde Comedor ID '
            + CAST(@ID_Comedor_Origen AS VARCHAR) + ' hacia Comedor ID '
            + CAST(@ID_Comedor_Destino AS VARCHAR) + '.';
    END
    ELSE
    BEGIN
        -- CASO B: Fallback al almacén central
        IF @ID_Almacen_Central IS NOT NULL
        BEGIN
            INSERT INTO Delivery (Fecha, ID_Comedor_Destino, ID_Almacen_Origen, ID_Comedor_Origen)
            VALUES (CAST(GETDATE() AS DATE), @ID_Comedor_Destino, @ID_Almacen_Central, NULL);

            PRINT 'LOGÍSTICA/ALERTA: Sin excedentes en zona "' + @Zona
                + '". Delivery generado desde Almacén Central (ID '
                + CAST(@ID_Almacen_Central AS VARCHAR) + ') hacia Comedor ID '
                + CAST(@ID_Comedor_Destino AS VARCHAR) + '.';
        END
    END
END;
GO

-- ----------------------------------------------------------------------------
-- usp_Donacion_ObtenerDestinoOptimo
-- Dado un donante, devuelve el comedor con mayor índice de urgencia
-- para orientar su donación hacia donde más se necesita.
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE usp_Donacion_ObtenerDestinoOptimo
    @DNI_Donante INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Donante WHERE DNI = @DNI_Donante)
    BEGIN
        RAISERROR('El donante con DNI %d no existe en el sistema.', 16, 1, @DNI_Donante);
        RETURN;
    END

    SELECT TOP 1
        v.ID_Comedor,
        v.Comedor                   AS Comedor_Recomendado,
        v.Zona,
        v.Prioridad,
        v.Stock_Actual,
        v.Unidades_Faltantes,
        v.Indice_Urgencia,
        'Recomendamos donar al comedor ' + v.Comedor
            + ' (Zona ' + v.Zona + '). Tiene ' + CAST(v.Stock_Actual AS VARCHAR)
            + ' unidades y necesita ' + CAST(v.Unidades_Faltantes AS VARCHAR)
            + ' más. Prioridad: ' + v.Prioridad + '.'  AS Mensaje_Al_Donante
    FROM VW_Ranking_Necesidad_Comedores v
    ORDER BY v.Indice_Urgencia DESC;
END
GO

/* ============================================================================
   SECCIÓN 10: CONSULTAS DE VERIFICACIÓN
   Ejecutar por separado para validar el sistema.
   ============================================================================ */
SELECT * From Comedor 
WHERE ID_Comedor = 4;

-- 1. Estado general de stock por comedor
SELECT * FROM VW_Stock_Actual_Por_Comedor
ORDER BY Stock_Actual ASC;

-- 2. Ranking de comedores con mayor necesidad
SELECT * FROM VW_Ranking_Necesidad_Comedores
ORDER BY Indice_Urgencia DESC;

-- 3. Consultar afiliados de un comedor específico con edad calculada
EXEC usp_Afiliado_Consultar @ID_Comedor = 1;

-- 4. Ver deliveries de un comedor (origen y destino)
EXEC usp_Delivery_ConsultarPorComedor @ID_Comedor = 4;

-- 5. Productos próximos a vencer (ventana de 60 días)
EXEC usp_Producto_ConsultarProximosAVencer @Dias_Limite = 60;

-- 6. Obtener destino óptimo de donación para un donante
EXEC usp_Donacion_ObtenerDestinoOptimo @DNI_Donante = 20123456;



----------------------------------------------- PRUEBAS -----------------------------------------------------------------
-- Simular faltante: eliminar productos de Villa Devoto para disparar trigger
-- (activa TR_Control_Stock_Bajas → Alerta_Stock → Aviso_Donantes → Logística)
DELETE FROM Ingresa WHERE ID_Producto IN (SELECT ID_Producto FROM Producto WHERE ID_Stock = 5);
DELETE FROM Dona WHERE ID_Producto IN (SELECT ID_Producto FROM Producto WHERE ID_Stock = 5);

-- Esto disparará el Trigger TR_Control_Stock_Bajas
DELETE FROM Producto WHERE ID_Stock = 5;

SELECT * FROM Delivery WHERE ID_Comedor_Destino = 5;
SELECT * FROM VW_Stock_Actual_Por_Comedor WHERE ID_Comedor IN (4, 5);
SELECT * FROM Alerta_Stock 
SELECT * FROM Aviso_Donante;




-- Insertar un producto simulando que vence en 5 días (hoy es junio 2026 en el contexto del script)
INSERT INTO Producto (Nombre, Unidad_de_Medida, Valor_de_Medida, Fecha_Vencimiento, ID_Stock, ID_Delivery) 
VALUES ('Leche Fresca Test', 'Litro', 1.00, DATEADD(DAY, 5, GETDATE()), 1, NULL);

-- Corroborar si el trigger detectó el vencimiento y creó la alerta
SELECT * FROM Alerta_Stock WHERE Tipo_Alerta = 'Proximo Vencimiento' ORDER BY Fecha_Alerta DESC;



-- Ejecutar el buscador de destino óptimo para el donante Roberto Alvarez (DNI 20123456)
EXEC usp_Donacion_ObtenerDestinoOptimo @DNI_Donante = 20123456;

----------------------------------------------- PRUEBAS -----------------------------------------------------------------
-- 8. Ver historial de alertas generadas
SELECT
    al.ID_Alerta,
    c.Nombre        AS Comedor,
    p.Nombre        AS Producto,
    al.Tipo_Alerta,
    al.Fecha_Alerta,
    al.Mensaje,
    CASE al.Resuelta WHEN 1 THEN 'Sí' ELSE 'No' END AS Resuelta
FROM Alerta_Stock al
INNER JOIN Stock   s ON al.ID_Stock    = s.ID_Stock
INNER JOIN Comedor c ON s.ID_Comedor   = c.ID_Comedor
LEFT  JOIN Producto p ON al.ID_Producto = p.ID_Producto
ORDER BY al.Fecha_Alerta DESC;

-- 9. Ver avisos pendientes por donante
SELECT
    av.ID_Aviso,
    d.Nombre + ' ' + d.Apellido         AS Donante,
    al.Mensaje                           AS Alerta,
    av.Fecha_Aviso,
    CASE av.Leido WHEN 1 THEN 'Leído' ELSE 'Pendiente' END AS Estado
FROM Aviso_Donante av
INNER JOIN Donante      d  ON av.DNI_Donante = d.DNI
INNER JOIN Alerta_Stock al ON av.ID_Alerta   = al.ID_Alerta
ORDER BY av.Fecha_Aviso DESC;

-- 10. Ver todos los deliveries con tipo de operación
SELECT
    d.ID_Delivery, d.Fecha,
    c_dest.Nombre                              AS Destino,
    COALESCE(al.Nombre, c_orig.Nombre)         AS Origen,
    CASE WHEN d.ID_Almacen_Origen IS NOT NULL
         THEN 'Almacen → Comedor'
         ELSE 'Comedor → Comedor' END          AS Tipo
FROM Delivery d
INNER JOIN Comedor c_dest ON d.ID_Comedor_Destino = c_dest.ID_Comedor
LEFT  JOIN Almacen al     ON d.ID_Almacen_Origen  = al.ID_Almacen
LEFT  JOIN Comedor c_orig ON d.ID_Comedor_Origen  = c_orig.ID_Comedor
ORDER BY d.Fecha DESC;
GO
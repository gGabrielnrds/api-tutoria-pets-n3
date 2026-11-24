-- 1. CRIAÇÃO DO BANCO E DAS TABELAS (3FN)
DROP DATABASE IF EXISTS db_tutoria_pets;
CREATE DATABASE db_tutoria_pets CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE db_tutoria_pets;

CREATE TABLE tutor (
    cpf VARCHAR(11) PRIMARY KEY,
    nome VARCHAR(120) NOT NULL,
    email VARCHAR(120) NOT NULL UNIQUE,
    senha VARCHAR(255) NOT NULL,
    total_pets INT NOT NULL DEFAULT 0,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE altura_pet (
    id_altura INT PRIMARY KEY AUTO_INCREMENT,
    altura VARCHAR(20) NOT NULL UNIQUE
);

CREATE TABLE pet (
    codigo_pet INT PRIMARY KEY AUTO_INCREMENT,
    nome_pet VARCHAR(100) NOT NULL,
    genero_pet VARCHAR(20) NOT NULL,
    altura_cm DECIMAL(5,2) NOT NULL,
    cpf_tutor VARCHAR(11) NOT NULL,
    id_altura INT NOT NULL,
    data_cadastro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pet_tutor FOREIGN KEY (cpf_tutor) REFERENCES tutor(cpf) ON DELETE CASCADE,
    CONSTRAINT fk_pet_altura FOREIGN KEY (id_altura) REFERENCES altura_pet(id_altura)
);

-- Carga inicial obrigatória da tabela de domínio altura_pet
INSERT INTO altura_pet (id_altura, altura) VALUES
(1, 'pequeno'),
(2, 'média'),
(3, 'alto');

-- 2. DOIS TRIGGERS (Classificação automática de altura e contador de pets)
DELIMITER $$

-- Trigger 1: Classifica automaticamente o porte do pet no INSERT
CREATE TRIGGER trg_classifica_altura_insert
BEFORE INSERT ON pet
FOR EACH ROW
BEGIN
    IF NEW.altura_cm <= 13 THEN
        SET NEW.id_altura = 1; -- pequeno
    ELSEIF NEW.altura_cm >= 14 AND NEW.altura_cm < 40 THEN
        SET NEW.id_altura = 2; -- média (brecha dos 14cm corrigida)
    ELSE
        SET NEW.id_altura = 3; -- alto
    END IF;
END$$

-- Trigger 2: Atualiza automaticamente o total_pets do tutor após INSERT
CREATE TRIGGER trg_incrementa_total_pets
AFTER INSERT ON pet
FOR EACH ROW
BEGIN
    UPDATE tutor
       SET total_pets = total_pets + 1
     WHERE cpf = NEW.cpf_tutor;
END$$

-- Trigger extra de apoio (garante consistência no UPDATE de altura e DELETE de pet)
CREATE TRIGGER trg_classifica_altura_update
BEFORE UPDATE ON pet
FOR EACH ROW
BEGIN
    IF NEW.altura_cm <= 13 THEN
        SET NEW.id_altura = 1;
    ELSEIF NEW.altura_cm >= 14 AND NEW.altura_cm < 40 THEN
        SET NEW.id_altura = 2;
    ELSE
        SET NEW.id_altura = 3;
    END IF;
END$$

CREATE TRIGGER trg_decrementa_total_pets
AFTER DELETE ON pet
FOR EACH ROW
BEGIN
    UPDATE tutor
       SET total_pets = GREATEST(total_pets - 1, 0)
     WHERE cpf = OLD.cpf_tutor;
END$$

DELIMITER ;

-- 3. DUAS VIEWS (Distintas das consultas da seção 5)

-- View 1: Catálogo público de pets (oculta CPF, e-mail e senha do tutor)
CREATE VIEW vw_catalogo_pets_publico AS
SELECT
    p.codigo_pet,
    p.nome_pet,
    p.genero_pet,
    p.altura_cm,
    a.altura AS porte,
    t.nome AS nome_tutor
FROM pet p
INNER JOIN altura_pet a ON p.id_altura = a.id_altura
INNER JOIN tutor t ON p.cpf_tutor = t.cpf;

-- View 2: Painel consolidado dos tutores com média de altura dos seus animais
CREATE VIEW vw_painel_tutores AS
SELECT
    t.cpf,
    t.nome,
    t.email,
    t.total_pets,
    COALESCE(ROUND(AVG(p.altura_cm), 2), 0) AS media_altura_pets_cm
FROM tutor t
LEFT JOIN pet p ON t.cpf = p.cpf_tutor
GROUP BY t.cpf, t.nome, t.email, t.total_pets;

-- 4. DUAS STORED PROCEDURES
DELIMITER $$

-- Procedure 1 (Escrita com parâmetros): Valida tutor e insere novo pet
CREATE PROCEDURE sp_cadastrar_pet_completo(
    IN p_nome_pet VARCHAR(100),
    IN p_genero_pet VARCHAR(20),
    IN p_altura_cm DECIMAL(5,2),
    IN p_cpf_tutor VARCHAR(11)
)
BEGIN
    DECLARE v_existe INT DEFAULT 0;

    SELECT COUNT(*) INTO v_existe FROM tutor WHERE cpf = p_cpf_tutor;

    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Erro: Tutor não encontrado com o CPF informado.';
    ELSE
        -- Passa id_altura = 1 como placeholder; o Trigger ajustará automaticamente
        INSERT INTO pet (nome_pet, genero_pet, altura_cm, cpf_tutor, id_altura)
        VALUES (p_nome_pet, p_genero_pet, p_altura_cm, p_cpf_tutor, 1);

        SELECT LAST_INSERT_ID() AS codigo_pet_gerado;
    END IF;
END$$

-- Procedure 2 (Consulta complexa parametrizada): Filtra pets por tutor e/ou porte
CREATE PROCEDURE sp_buscar_pets_filtrado(
    IN p_cpf_tutor VARCHAR(11),
    IN p_altura_nome VARCHAR(20)
)
BEGIN
    SELECT
        p.codigo_pet,
        p.nome_pet,
        p.genero_pet,
        p.altura_cm,
        a.altura AS classificacao_altura,
        t.cpf AS cpf_tutor,
        t.nome AS nome_tutor,
        t.email AS email_tutor
    FROM pet p
    INNER JOIN altura_pet a ON p.id_altura = a.id_altura
    INNER JOIN tutor t ON p.cpf_tutor = t.cpf
    WHERE (p_cpf_tutor IS NULL OR p.cpf_tutor = p_cpf_tutor)
      AND (p_altura_nome IS NULL OR a.altura = p_altura_nome)
    ORDER BY p.codigo_pet ASC;
END$$

DELIMITER ;

-- 5. DADOS INICIAIS DE TESTE E AS 3 CONSULTAS COMPLEXAS EXIGIDAS
INSERT INTO tutor (cpf, nome, email, senha) VALUES
('11122233344', 'Gabriel Nardes', 'gabriel@email.com', '$2a$10$hashExemploApenasParaTesteInicial001'),
('55566677788', 'Mariana Costa', 'mariana@email.com', '$2a$10$hashExemploApenasParaTesteInicial002');

-- Testando as bordas (12cm = pequeno, 14cm = média, 45cm = alto)
INSERT INTO pet (nome_pet, genero_pet, altura_cm, cpf_tutor, id_altura) VALUES
('Pipoca', 'Fêmea', 12.00, '11122233344', 1),
('Thor', 'Macho', 14.00, '11122233344', 1),
('Rex', 'Macho', 45.00, '55566677788', 1);

-- CONSULTA 1 (Mínimo 3 tabelas: pet + tutor + altura_pet)
SELECT
    p.codigo_pet,
    p.nome_pet,
    p.genero_pet,
    p.altura_cm,
    a.altura AS porte,
    t.nome AS tutor,
    t.email AS contato_tutor
FROM pet p
INNER JOIN tutor t ON p.cpf_tutor = t.cpf
INNER JOIN altura_pet a ON p.id_altura = a.id_altura
ORDER BY p.altura_cm DESC;

-- CONSULTA 2 (Mínimo 2 tabelas: altura_pet + pet - Estatísticas por porte)
SELECT
    a.altura AS classificacao_porte,
    COUNT(p.codigo_pet) AS quantidade_pets,
    COALESCE(ROUND(AVG(p.altura_cm), 2), 0) AS altura_media_cm,
    COALESCE(MAX(p.altura_cm), 0) AS maior_altura_cm
FROM altura_pet a
LEFT JOIN pet p ON a.id_altura = p.id_altura
GROUP BY a.id_altura, a.altura;

-- CONSULTA 3 (Mínimo 2 tabelas: tutor + pet - Distribuição de gênero por tutor)
SELECT
    t.cpf,
    t.nome AS tutor,
    SUM(CASE WHEN p.genero_pet = 'Macho' THEN 1 ELSE 0 END) AS total_machos,
    SUM(CASE WHEN p.genero_pet = 'Fêmea' THEN 1 ELSE 0 END) AS total_femeas,
    COUNT(p.codigo_pet) AS total_geral
FROM tutor t
LEFT JOIN pet p ON t.cpf = p.cpf_tutor
GROUP BY t.cpf, t.nome;
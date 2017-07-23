-- phpMyAdmin SQL Dump
-- version 4.6.4
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Jul 23, 2017 at 10:42 PM
-- Server version: 5.7.14
-- PHP Version: 5.6.25

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `sampdb`
--

-- --------------------------------------------------------

--
-- Table structure for table `players`
--

CREATE TABLE `players` (
  `id` int(11) NOT NULL,
  `username` varchar(24) NOT NULL,
  `password` char(64) NOT NULL,
  `salt` char(16) NOT NULL,
  `kills` mediumint(8) NOT NULL DEFAULT '0',
  `deaths` mediumint(8) NOT NULL DEFAULT '0',
  `x` float NOT NULL DEFAULT '0',
  `y` float NOT NULL DEFAULT '0',
  `z` float NOT NULL DEFAULT '0',
  `angle` float NOT NULL DEFAULT '0',
  `interior` tinyint(3) NOT NULL DEFAULT '0',
  `HelperLevel` int(11) NOT NULL DEFAULT '0'
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Dumping data for table `players`
--

INSERT INTO `players` (`id`, `username`, `password`, `salt`, `kills`, `deaths`, `x`, `y`, `z`, `angle`, `interior`, `HelperLevel`) VALUES
(1, 'Maurice', '86A7A7F691CA48CE0F47A7D84D0EC14C86DC358E46DF35162CA452396C6A8E41', '8TqYab`1"0.cH8Ni', 0, 0, 2052.45, 1342.01, 10.6719, 346.049, 0, 2),
(2, 'Yamato', '86A7A7F691CA48CE0F47A7D84D0EC14C86DC358E46DF35162CA452396C6A8E41', '8TqYab`1"0.cH8Ni', 0, 5, 2063.26, -2166.71, 27.8017, 188.498, 0, 0);

--
-- Indexes for dumped tables
--

--
-- Indexes for table `players`
--
ALTER TABLE `players`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `username` (`username`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `players`
--
ALTER TABLE `players`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;

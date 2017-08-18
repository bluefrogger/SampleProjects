--===== Suppress the auto-display of rowcounts so as not to interfere with the returned
     -- result set
    SET NOCOUNT ON

--=================================================================================================
--      Local variables
--=================================================================================================
--===== These are processing control and reporting variables
DECLARE @Counter          INT          --General purpose counter
DECLARE @CurrentName      VARCHAR(256) --Name of file currently being worked
DECLARE @DirTreeCount     INT          --Remembers number of rows for xp_DirTree
DECLARE @IsFile           BIT          --1 if Name is a file, 0 if not

--===== These are object "handle" variables
DECLARE @ObjFile          INT          --File object
DECLARE @ObjFileSystem    INT          --File System Object  

--===== These variable names match the sp_OAGetProperty options
     -- Made names match so they're less confusing
DECLARE @Attributes       INT          --Read only, Hidden, Archived, etc, as a bit map
DECLARE @DateCreated      DATETIME     --Date file was created
DECLARE @DateLastAccessed DATETIME     --Date file was last read (accessed)
DECLARE @DateLastModified DATETIME     --Date file was last written to
DECLARE @Name             NVARCHAR(128) --File Name and Extension
DECLARE @Path             NVARCHAR(200) --Full path including file name
DECLARE @ShortName        VARCHAR(12)  --8.3 file name
DECLARE @ShortPath        VARCHAR(100) --8.3 full path including file name
DECLARE @Size             INT          --File size in bytes
DECLARE @Type             VARCHAR(100) --Long Windows file type (eg.'Text Document',etc)

--=================================================================================================
--      Create temporary working tables
--=================================================================================================
--===== Create a place to store all file names derived from xp_DirTree
     IF OBJECT_ID('TempDB..#DirTree','U') IS NOT NULL
        DROP TABLE #DirTree

 CREATE TABLE #DirTree
        (
        RowNum INT IDENTITY(1,1),
        Name   VARCHAR(256) PRIMARY KEY CLUSTERED, 
        Depth  BIT, 
        IsFile BIT
        )

--===== Create a place to store the file details so we can return all the file details
     -- as a single result set
     IF OBJECT_ID('TempDB..#FileDetails','U') IS NOT NULL
        DROP TABLE #FileDetails

 CREATE TABLE #FileDetails
        (
        RowNum           INT IDENTITY(1,1) PRIMARY KEY CLUSTERED,
        Name             NVARCHAR(128), --File Name and Extension
        Path              NVARCHAR(200), --Full path including file name
        ShortName        VARCHAR(12),  --8.3 file name
        ShortPath        VARCHAR(100), --8.3 full path including file name
        DateCreated      DATETIME,     --Date file was created
        DateLastAccessed DATETIME,     --Date file was last read
        DateLastModified DATETIME,     --Date file was last written to
        Attributes       INT,          --Read only, Compressed, Archived
        ArchiveBit       AS CASE WHEN Attributes&  32=32   THEN 1 ELSE 0 END,
        CompressedBit    AS CASE WHEN Attributes&2048=2048 THEN 1 ELSE 0 END,
        ReadOnlyBit      AS CASE WHEN Attributes&   1=1    THEN 1 ELSE 0 END,
        Size             INT,          --File size in bytes
        Type             VARCHAR(100)  --Long Windows file type (eg.'Text Document',etc)
        )

--=================================================================================================
--      Make sure the full path name provided ends with a backslash
--=================================================================================================
 
 SELECT @piFullPath = @piFullPath+'\'
  WHERE RIGHT(@piFullPath,1)<>'\'

--=================================================================================================
--      Get all the file names for the directory (includes directory names as IsFile = 0)
--=================================================================================================
--===== Get the file names for the desired path
     -- Note that xp_DirTree is available in SQL Server 2000, 2005, and 2008.
 INSERT INTO #DirTree (Name, Depth, IsFile)
   EXEC Master.dbo.xp_DirTree @piFullPath,1,1 -- Current diretory only, list file names

     -- Remember the row count
    SET @DirTreeCount = @@ROWCOUNT


--===== Update the file names with the path for ease of processing later on
 UPDATE #DirTree
    SET Name = @piFullPath + Name

--=================================================================================================
--      Get the properties for each file.  This is one of the few places that a WHILE
--      loop is required in T-SQL because sp_OA is as dumb as a fart-sack full of broken antlers.
--=================================================================================================
--===== Create a file system object and remember the "handle"
   EXEC dbo.sp_OACreate 'Scripting.FileSystemObject', @ObjFileSystem OUT

--===== Step through the file names and get the properties for each file.
    SET @Counter = 1
  WHILE @Counter <= @DirTreeCount
  BEGIN
        --===== Get the current name and see if it's a file
         SELECT @CurrentName = Name,
                @IsFile = IsFile
           FROM #DirTree 
          WHERE RowNum = @Counter
        
        --===== If it's a file, get the details for it
             IF @IsFile = 1 AND @CurrentName LIKE '%%'
          BEGIN
                --===== Create an object for the path/file and remember the "handle"
                   EXEC dbo.sp_OAMethod @ObjFileSystem,'GetFile', @ObjFile OUT, @CurrentName
                
                --===== Get the all the required attributes for the file itself
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'Path',             @Path             OUT
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'ShortPath',        @ShortPath        OUT
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'Name',             @Name             OUT
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'ShortName',        @ShortName        OUT
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'DateCreated',      @DateCreated      OUT
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'DateLastAccessed', @DateLastAccessed OUT
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'DateLastModified', @DateLastModified OUT
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'Attributes',       @Attributes       OUT
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'Size',             @Size             OUT
                   EXEC dbo.sp_OAGetProperty @ObjFile, 'Type',             @Type             OUT
        
                --===== Insert the file details into the return table        
                 INSERT INTO #FileDetails
                        (Path, ShortPath, Name, ShortName, DateCreated, 
                         DateLastAccessed, DateLastModified, Attributes, Size, Type)
                 SELECT @Path,@ShortPath,@Name,@ShortName,@DateCreated, 
                        @DateLastAccessed,@DateLastModified,@Attributes,@Size,@Type
            END
        
        --===== Increment the loop counter to get the next file or quit
         SELECT @Counter = @Counter + 1
    END

--===== House keeping, destroy and drop the file objects to keep memory leaks from happening
   EXEC sp_OADestroy @ObjFileSystem
   EXEC sp_OADestroy @ObjFile

--===== Return the details for all the files as a single result set.
     -- This is one of the few places in T-SQL where SELECT * is ok.
     -- If you don't think so, go look at some of the MS stored procedures.  [Wink] 
 SELECT * FROM #FileDetails
/*	"probeOs.c"

	Small utility that makes educated guesses at the OS/Kernel in a
	VM under management by libvirt.

	Immense thanks to Harlan Carvey (keydet89@yahoo.com), so his original
	perl utility, "kern.pl" (v.0.1_20060914).
*/

// https://en.wikibooks.org/wiki/X86_Disassembly/Windows_Executable_Files#MS-DOS_header
// https://www.blackhat.com/presentations/bh-usa-06/BH-US-06-Burdach.pdf

#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libvirt/libvirt.h>

static const char *szUri = "qemu+tls://ostara/system";

static const int DEBUG = 0;

#define CP() do { if (DEBUG) printf ("checkpoint: %d\n", __LINE__); } while (0)

static unsigned int MAX_MEM_RANGE = 65536;
static unsigned short RT_VERSION = 0x10;

/* Table of physical addresses to check for the MZ/PE header for "NTOSKRNL.EXE". */
/* Shamelessly taken from Harlan Carvey. */
static unsigned long win32_krnl_offsets[] =
{
	0x00100000,		// NT4
	0x00400000,		// 2000
	0x004d4000,		// XP
	0x004d0000,		// XP
	0x004d5000,		// XP
	0x00a02000,		// XP
	0x004d7000,		// XP-SP2
	0x004de000,		// 2003
	0x00800000,		// 2003-SP1
	(unsigned long)-1,	// end of list.
};

struct COFFHeader
{
	unsigned short int Machine;			// 2 bytes
	unsigned short int NumberOfSections;		// 2 bytes
	unsigned int TimeDateStamp;			// 4 bytes
	unsigned int PointerToSymbolTable;		// 4 bytes
	unsigned int NumberOfSymbols;			// 4 bytes
	unsigned short int SizeOfOptionalHeader;	// 2 bytes
	unsigned short int Characteristics;		// 2 bytes
};

struct data_directory
{
	unsigned int	VirtualAddress;
	unsigned int	Size;
};

struct PEOptHeader
{
	unsigned short	signature;		//decimal number 267.
	unsigned char	MajorLinkerVersion;
	unsigned char	MinorLinkerVersion;
	unsigned int	SizeOfCode;
	unsigned int	SizeOfInitializedData;
	unsigned int	SizeOfUninitializedData;
	unsigned int	AddressOfEntryPoint;	// The RVA of the code entry point
	unsigned int	BaseOfCode;
	unsigned int	BaseOfData;
	unsigned int	ImageBase;
	unsigned int	SectionAlignment;
	unsigned int	FileAlignment;
	unsigned short	MajorOSVersion;
	unsigned short	MinorOSVersion;
	unsigned short	MajorImageVersion;
	unsigned short	MinorImageVersion;
	unsigned short	MajorSubsystemVersion;
	unsigned short	MinorSubsystemVersion;
	unsigned int	Reserved;
	unsigned int	SizeOfImage;
	unsigned int	SizeOfHeaders;
	unsigned int	Checksum;
	unsigned short	Subsystem;
	unsigned short	DLLCharacteristics;
	unsigned int	SizeOfStackReserve;
	unsigned int	SizeOfStackCommit;
	unsigned int	SizeOfHeapReserve;
	unsigned int	SizeOfHeapCommit;
	unsigned int	LoaderFlags;
	unsigned int	NumberOfRvaAndSizes;
	struct data_directory DataDirectory[16];     // Can have any number of elements, matching the number in NumberOfRvaAndSizes.
};

static const int IMAGE_DIRECTORY_ENTRY_EXPORT = 0;		// Location of the export directory
static const int IMAGE_DIRECTORY_ENTRY_IMPORT = 1;		// Location of the import directory
static const int IMAGE_DIRECTORY_ENTRY_RESOURCE = 2;		// Location of the resource directory
static const int IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT = 11;	// Location of alternate import-binding directory

struct	ImageSectionHeader		// 40 bytes
{
	char		sName[8];	// 8 bytes, NOT guaranteed to be terminated.
	unsigned int	nVirtSize;	// 4 bytes, size once loaded into memory.
	unsigned int	nVirtAddr;	// 4 bytes, location once loaded into memory.
	unsigned int	nPhysSize;	// 4 bytes, size on disk.
	unsigned int	nPhysAddr;	// 4 bytes, offset in file on disk.
	unsigned char	zReserved[12];	// 12 bytes, usually zero.
	unsigned int	nSectionFlags;	// 4 bytes
};

// Win32 reource directory table headr (16 bytes)
// Named "IMAGE_RESOURCE_DIRECTORY" in the msdn (I abbreviated)
struct	IMG_RES_DIR_HDR
{
	unsigned int	cCharacteristics;	// 4 bytes, flags
	unsigned int	nDateTimeStamp;		// 4 bytes, unix time stamp
	unsigned short	nMajorVersion;		// 2 bytes
	unsigned short	nMinorVersion;		// 2 bytes
	unsigned short	nCountNames;		// 2 bytes, count of "name" entries.
	unsigned short	nCountIDs;		// 2 bytes, count of "id" entries.
};

// Named "IMAGE_RESOURCE_DIRECTORY_ENTRY"
struct	IMG_RES_DIR_ENTRY
{
	unsigned int		nName;
	unsigned int		nDataOffset;
};

struct	IMG_RES_DIR
{
	struct IMG_RES_DIR_HDR		header;
	struct IMG_RES_DIR_ENTRY	entry[1];
};

struct	RES_DATA_ENTRY
{
	unsigned int		nDataRva;	// 4 bytes
	unsigned int		nSize;		// 4 bytes
	unsigned int		nCodePage;	// 4 bytes
	unsigned int		nReserved;	// 4 bytes
};

struct	FIXED_FILE_INFO		// "VS_FIXEDFILEINFO", count 13, 4-byte dwords.
{
	unsigned int		dwSignature;
	unsigned int		dwStructVersion;
	unsigned int		dwFileVersionMS;
	unsigned int		dwFileVersionLS;
	unsigned int		dwProductVersionMS;
	unsigned int		dwProductVersionLS;
	unsigned int		dwFileFlagsMask;
	unsigned int		dwFileFlags;
	unsigned int		dwFileOS;
	unsigned int		dwFileType;
	unsigned int		dwFileSubtype;
	unsigned int		dwFileDateMS;
	unsigned int		dwFileDateLS;
};

// Stuff from the 'VS_VERSIONINFO'

struct	WindowsVersionInfo
{
	struct FIXED_FILE_INFO	ffi;

// The following are NOT loaded from the unicode strings yet (I'm too lazy and don't need them).
//	char	*szFileDescription;
//	char	*szFileVersion;
//	char	*szInternalName;
//	char	*szOriginalFileName;
//	char	*szProductName;
//	char	*szProductVersion;
};

// This struct represents what we are trying to find in the domain's RAM:
// The win32 file info for the OS.
struct Win32Kernel
{
	unsigned long			nBaseAddr;	// Where the kernel is loaded ("MZ" header)
	struct WindowsVersionInfo	vi;
};

struct DomainKernelInfo
{
	unsigned int			nKernelType;	// 0 = Microsoft
	union {
		struct Win32Kernel	win32;
	} 				info;
};



// Like a "VFS" for accessing memory from a domain.
struct		domWrapper
{
	virDomainPtr	pDom;
	unsigned long	nKB;
	unsigned long long nBaseAddr;
	unsigned char	*pBuffer;
	unsigned long	nBufSize;
	int		nFlags;		// DMW_xxxxx
};

static const unsigned int DMW_VALID = 0x0001;

static struct domWrapper*	domWrapperAlloc (virDomainPtr pDom)
{
	struct domWrapper *p = NULL;

	if (NULL == pDom)
	{
		return NULL;
	}

	if (NULL == (p = (struct domWrapper*)malloc (sizeof (*p))))
	{
		return NULL;
	}

	memset (p, 0, sizeof(*p));

	p->pDom = pDom;
	p->nKB = virDomainGetMaxMemory (pDom);
	p->nBaseAddr = 0;
	p->nBufSize = 65536;
	if (NULL == (p->pBuffer = (unsigned char*)malloc (p->nBufSize)))
	{
		free (p);
		return NULL;
	}
	memset (p->pBuffer, 0, p->nBufSize);
	p->nFlags = 0;

	return p;
}

static void	domWrapperDestroy (struct domWrapper *pDMW)
{
	if (pDMW)
	{
		if (pDMW->pBuffer)
		{
			free (pDMW->pBuffer);
		}

		free (pDMW);
	}
}

// Copies 'nBytes' bytes from nAbsAddr in the domain (physical memory) into 'pBuffer'.
// Returns '1' on success, '0' on failure.
// We expect many copy operations to come from the same "block", so we cache a 64K chunk
// of the domain's memory.
static int	domWrapperCopy (struct domWrapper *pDomWrapper, unsigned long int nAbsAddr, unsigned int nBytes, void *pBuffer)
{
	if (!pDomWrapper || !nBytes || !pBuffer || (nBytes > MAX_MEM_RANGE) || (nBytes > pDomWrapper->nBufSize))
	{
		return 0;
	}

	if (!(pDomWrapper->nFlags & DMW_VALID) ||
	    (nAbsAddr < pDomWrapper->nBaseAddr) ||
	    ((nAbsAddr + nBytes) >= (pDomWrapper->nBaseAddr + pDomWrapper->nBufSize)))
	{
//		printf ("INFO: virDomainMemoryPeek (%08lx, %lu)\n", nAbsAddr, pDomWrapper->nBufSize);
		if (0 != virDomainMemoryPeek (pDomWrapper->pDom, nAbsAddr, pDomWrapper->nBufSize, pDomWrapper->pBuffer, VIR_MEMORY_PHYSICAL))
		{
			pDomWrapper->nFlags &= ~DMW_VALID;
			return 0;
		}

		pDomWrapper->nFlags |= DMW_VALID;
		pDomWrapper->nBaseAddr = nAbsAddr;
	}

	memcpy (pBuffer, pDomWrapper->pBuffer + (nAbsAddr - pDomWrapper->nBaseAddr), nBytes);
	return 1;
}

/* Quick little tool to aid in development + debugging. */
static void	hexDump (const void *buf, unsigned int count, unsigned long int baseAddr)
{
	const unsigned char *p = (const unsigned char *)buf;
//	unsigned long int newBase = baseAddr & (unsigned long int)(~0xf);

//	printf ("ba = %lu, nb = %lu\n", baseAddr, newBase);

	while (count)
	{
		printf (" %02x", *p);
		p++;
		count--;
	}
	printf ("\n");
}

static void	dumpCoffHeader (const struct COFFHeader *pCoff)
{
	printf ("\tCOFF: "); hexDump (pCoff, sizeof(*pCoff), 0);
	printf ("\tcoff.Machine = %04x\n", pCoff->Machine);
	printf ("\tcoff.NumberOfSections = %04x\n", pCoff->NumberOfSections);
	printf ("\tcoff.TimeDateStamp = %08x\n", pCoff->TimeDateStamp);
	printf ("\tcoff.PointerToSymbolTable = %08x\n", pCoff->PointerToSymbolTable);
	printf ("\tcoff.NumberOfSymbols = %04x\n", pCoff->NumberOfSymbols);
	printf ("\tcoff.SizeOfOptionalHeader = %04x\n", pCoff->SizeOfOptionalHeader);
	printf ("\tcoff.Characteristics = %04x\n", pCoff->Characteristics);
}

static void	dumpPEHeader (const struct PEOptHeader *peOpt)
{
	printf ("\tPE.SubSystem = %d\n", peOpt->Subsystem);
	printf ("\tPE.rva_num = %d\n", peOpt->NumberOfRvaAndSizes);

// Loop through the RVA sections.
	for (int i = 0; i < peOpt->NumberOfRvaAndSizes; i++)
	{
		if (!peOpt->DataDirectory[i].VirtualAddress && !peOpt->DataDirectory[i].Size)
		{
			continue;
		}

		printf ("\tpe.rva[%2d] = %08x, %08x\n", i, peOpt->DataDirectory[i].VirtualAddress, peOpt->DataDirectory[i].Size);
	}
}

static struct IMG_RES_DIR*	loadImgResDir (struct domWrapper *pDomWrapper, unsigned long baseAddr, unsigned long nImgResDirPtr)
{
	struct IMG_RES_DIR	*pDir = NULL;
	struct IMG_RES_DIR_HDR	hdr = {0};
	unsigned int		nBytes = 0;

	if (!pDomWrapper || !baseAddr || !nImgResDirPtr)
	{
		CP(); return NULL;
	}

// Step #1, read the header.
	if (!domWrapperCopy (pDomWrapper, baseAddr + nImgResDirPtr, sizeof (hdr), &hdr))
	{
		CP(); return NULL;
	}

// Step #2, allocate full buffer.
	nBytes = sizeof(hdr) + sizeof(struct IMG_RES_DIR_ENTRY) * (hdr.nCountNames + hdr.nCountIDs);
	if (NULL == (pDir = (struct IMG_RES_DIR*)malloc (nBytes)))
	{
		CP(); return NULL;
	}

// Step #3, read entire IMG_RES_DIR.
	if (!domWrapperCopy (pDomWrapper, baseAddr + nImgResDirPtr, nBytes, pDir))
	{
		free (pDir);
		CP(); return NULL;
	}

// Debugging
#if 0
	printf ("RES [%08lx] = ", nImgResDirPtr);
	hexDump (pDir, 16, 0);
	for (unsigned int i = 0; i < (hdr.nCountNames + hdr.nCountIDs); i++)
	{
		printf ("\tver[%2d] = %08x, %08x\n", i, pDir->entry[i].nName, pDir->entry[i].nDataOffset);
	}
#endif

	return pDir;
}

// http://msdn.microsoft.com/en-us/library/ms809762.aspx
// ~80% down the page, under "PE File Resources"
static struct WindowsVersionInfo*	findVersionInfo (struct domWrapper *pDomWrapper, unsigned long baseAddr, unsigned int nImgResDirPtr)
{
	struct WindowsVersionInfo *pVer = NULL;
	struct IMG_RES_DIR *pTypes = NULL;	// level-0
	struct IMG_RES_DIR *pNames = NULL;	// level-1
	struct IMG_RES_DIR *pLangs = NULL;	// level-2
	struct RES_DATA_ENTRY dataEntry = {0};
	struct FIXED_FILE_INFO ffi = {0};
	unsigned int i = 0;
	unsigned int nCount = 0;
	unsigned int nOffset = 0;

	if (!pDomWrapper || !baseAddr || !nImgResDirPtr)
	{
		CP(); goto done;
	}

// The ".rscs" is a tree structure.  Most actual resource content is three layers down.

// Step #1, load the root entry.  It contains a table of each resource type
	if (NULL == (pTypes = loadImgResDir (pDomWrapper, baseAddr, nImgResDirPtr)))
	{
		CP(); goto done;
	}

// Step #2, locate the "RT_VERSION" resource directory entry.
	nCount = pTypes->header.nCountNames + pTypes->header.nCountIDs;
	if (!nCount) { CP(); goto done; }
	for (i = 0; (i < nCount) && (pTypes->entry[i].nName != RT_VERSION); i++);

// Step 2.5, sanity checking.
	if (i >= nCount) { CP(); goto done; }
	if (!(pTypes->entry[i].nDataOffset & 0x80000000)) { CP(); goto done; }

// Step #3, load the table of names for the selected type.
// There should be one entry each each resource of this type.
// Generally "RT_VERSION" should have ony one entry.
	nOffset = nImgResDirPtr + (pTypes->entry[i].nDataOffset & 0x7fffffff);
	if (NULL == (pNames = loadImgResDir (pDomWrapper, baseAddr, nOffset )))
	{
		CP(); goto done;
	}

// Step #3.5, sanity checking on language table.
	nCount = pNames->header.nCountNames + pNames->header.nCountIDs;
	if (!nCount) { CP(); goto done; }
	if (!(pNames->entry[0].nDataOffset & 0x80000000)) { CP(); goto done; }

// Step #4, Ignore the name, just take the first (and usually only) entry.
// This is the table of languages.  RT_VERSION typically has only one entry.
	nOffset = nImgResDirPtr + (pNames->entry[0].nDataOffset & 0x7fffffff);
	if (NULL == (pLangs = loadImgResDir (pDomWrapper, baseAddr, nOffset )))
	{
		CP(); goto done;
	}

	nCount = pLangs->header.nCountNames + pLangs->header.nCountIDs;
	if (!nCount) { CP(); goto done; }

// Should be a "leaf" node.
	if (pLangs->entry[0].nDataOffset & 0x80000000) { CP(); goto done; }

// Load the leaf node (8 bytes)
	nOffset = nImgResDirPtr + (pLangs->entry[0].nDataOffset & 0x7fffffff);
	if (!domWrapperCopy (pDomWrapper, baseAddr + nOffset, sizeof(dataEntry), &dataEntry))
	{
		CP(); goto done;
	}

// Step #4.5, sanity checking.
	if (dataEntry.nSize > 16384) { CP(); goto done; }	// random guess at reasonable limit.

// Step #5, load the "VS_FIXEDFILEINFO" part of the resource.
	nOffset = dataEntry.nDataRva + 6 + 0x22;
	if (!domWrapperCopy (pDomWrapper, baseAddr + nOffset, sizeof(ffi), &ffi))
	{
		CP(); goto done;
	}

	if (ffi.dwSignature != 0xFEEF04BD)
	{
		CP(); goto done;
	}

	if (NULL == (pVer = malloc (sizeof(*pVer))))
	{
		CP(); goto done;
	}

	pVer->ffi = ffi;

done:
	if (pTypes) free (pTypes);
	if (pNames) free (pNames);
	if (pLangs) free (pLangs);

	return pVer;
}

// Scan memory of domain, looking for a matching win32 kernel image ("ntoskrnl.exe")
static struct WindowsVersionInfo*	probeWin32Kernel (struct domWrapper *pDomWrapper, unsigned long baseAddr)
{
	unsigned long		e_lfanew = 0;
	unsigned int 		rvaPEOptionHeader = 0;
	unsigned int 		rvaSectionHeaders = 0;
	unsigned int 		i = 0;
	unsigned char		mz_hdr[4096];
	struct COFFHeader	coff = {0};
	struct PEOptHeader	peOpt = {0};
	struct ImageSectionHeader rscsHdr = {"", 0};
	unsigned char 		*pBuffer = mz_hdr + 0;	// Alias, for brevity.
	struct WindowsVersionInfo *pVer = NULL;

// FIXME: big-ass-assumption: the MZ header, PE header both fit within the first 4K of the image.
	if (!domWrapperCopy (pDomWrapper, baseAddr, sizeof (mz_hdr), mz_hdr))
	{
		CP(); return NULL;
	}

// Check for "MZ" header.
	if (0x5a4d != *(unsigned short int*)(pBuffer + 0))
	{
		CP(); goto fail;
	}

// Get offset from MZ header to the PE header (aka, "e_lfanew" value).
	e_lfanew = *(unsigned int*)(pBuffer + 0x3c);
	if (e_lfanew > (sizeof(mz_hdr) - 4))
	{
		CP(); goto fail;
	}

// The PE header should be 8-byte aligned.
	if (e_lfanew & 0x7)
	{
		CP(); goto fail;
	}

// Check for PE header.
	if (0x00004550 != *(unsigned int*)(pBuffer + e_lfanew))
	{
		CP(); goto fail;
	}

// COFF header immediately follows PE header.
	if (!domWrapperCopy (pDomWrapper, baseAddr + e_lfanew + 4, sizeof(coff), &coff))
	{
		CP(); goto fail;
	}

// Sanity check the COFF header.
	if (coff.Machine != 0x14C)	// magic code for "i386"
	{
		CP(); goto fail;
	}

// According to wikibooks, all PE headers are a fixed size (even though thry could be variable).
	if (coff.SizeOfOptionalHeader != sizeof (struct PEOptHeader))
	{
		CP(); goto fail;
	}

//	dumpCoffHeader (&coff);

// Grab the PE "optional" (not really) header.
	rvaPEOptionHeader = e_lfanew + 24;
	if (!domWrapperCopy (pDomWrapper, baseAddr + rvaPEOptionHeader, coff.SizeOfOptionalHeader, &peOpt))
	{
		CP(); goto fail;
	}

// Yeah for magic numbers.  (See wikibooks article).
	if (peOpt.signature != 267)
	{
		CP(); goto fail;
	}

//	dumpPEHeader (&peOpt);
//	printf ("\tMZ header @ %08lx\n", baseAddr);
//	printf ("\tPE.DataDirectory @ %08lx\n", baseAddr + e_lfanew + 24 + offsetof (struct PEOptHeader, DataDirectory));

	struct data_directory	ddRes = {0};		// for brevity
	memcpy (&ddRes, peOpt.DataDirectory + IMAGE_DIRECTORY_ENTRY_RESOURCE, sizeof(ddRes));
	if (!ddRes.VirtualAddress || !ddRes.Size)
	{
		CP(); goto fail;
	}

// The "Section Headers" immediately follow the DataDirectory.
// Source: Page 23, Revision 8.2 (2010-09-21), "pecoff_v8", Microsoft Inc.

// Loop through each section, looking for ".rscs" (resources)
	rvaSectionHeaders = rvaPEOptionHeader + coff.SizeOfOptionalHeader;
	for (i = 0; i < coff.NumberOfSections; i++)
	{
		unsigned int offRscs = i * sizeof (struct ImageSectionHeader);

		if (!domWrapperCopy (pDomWrapper, baseAddr + rvaSectionHeaders + offRscs, sizeof (rscsHdr), &rscsHdr))
		{
			CP(); goto fail;
		}

		if (!memcmp (rscsHdr.sName, ".rsrc\0\0\0", 8))
		{
			break;
		}
	}

	if (i >= coff.NumberOfSections)
	{
		CP(); goto fail;
	}

// Sanity check.
	if (rscsHdr.nVirtAddr != ddRes.VirtualAddress)
	{
		CP(); goto fail;
	}

	if (NULL == (pVer = findVersionInfo (pDomWrapper, baseAddr, rscsHdr.nVirtAddr)))
	{
		CP(); goto fail;
	}

	return pVer;

fail:
	return NULL;
}

// Given a domain, attempt to determine its operatin system.
static void	processDomain (virDomainPtr pDom)
{
	const char *name = NULL;
	unsigned long kb = 0;	// RAM, in kilobytes.
	int		i = 0;
	struct domWrapper	*pDomWrapper = NULL;

	if (!pDom) return;
	name = virDomainGetName (pDom);
	if (!name) return;

//	printf ("Probing: %s\n", name);

	kb = virDomainGetMaxMemory (pDom);
//	printf ("\tRAM = %lu KiB\n", kb);

	if (NULL == (pDomWrapper = domWrapperAlloc (pDom)))
	{
		CP(); return;
	}

	for (i = 0; win32_krnl_offsets[i] != (unsigned long)-1; i++)
	{
		struct WindowsVersionInfo *pVer = probeWin32Kernel (pDomWrapper, win32_krnl_offsets[i]);
		if (!pVer) continue;

		char ver[64];
		snprintf (ver, sizeof(ver), "%d.%d.%d.%d",
			pVer->ffi.dwProductVersionMS >> 16,
			pVer->ffi.dwProductVersionMS & 0xffff,
			pVer->ffi.dwProductVersionLS >> 16,
			pVer->ffi.dwProductVersionLS & 0xffff);

		printf ("%-20.20s  %6luKiB  [%08lx] %s\n", name, kb, win32_krnl_offsets[i], ver);
		break;
	}

	domWrapperDestroy (pDomWrapper);
}

int	main (int argc, char *argv[])
{
	virConnectPtr	pVmm = NULL;
	virDomainPtr	pDom = NULL;
	int		numDomains = 0;
	int		i;
	int		*domainIds = NULL;

	assert (sizeof(struct COFFHeader) == 20);
	assert (sizeof(struct ImageSectionHeader) == 40);
	assert (sizeof(struct IMG_RES_DIR_HDR) == 16);
	assert (sizeof(struct IMG_RES_DIR_ENTRY) == 8);
	assert (sizeof(struct RES_DATA_ENTRY) == 16);

	if (NULL == (pVmm = virConnectOpen (szUri)))
	{
		fprintf (stderr, "Failed to connect: %s\n", szUri);
		exit (-1);
	}

	if (-1 == (numDomains = virConnectNumOfDomains(pVmm)))
	{
		goto done;
	}

	if (NULL == (domainIds = malloc(sizeof(int) * numDomains)))
	{
		goto done;
	}

	if (-1 == (numDomains = virConnectListDomains (pVmm, domainIds, numDomains)))
	{
		goto done;
	}

	for (i = 0; i < numDomains; i++)
	{
		if (NULL != (pDom = virDomainLookupByID (pVmm, domainIds[i])))
		{
			processDomain (pDom);
		}
	}

done:
	if (domainIds)
	{
		free (domainIds);
	}

	if (pVmm)
	{
		virConnectClose (pVmm);
	}

	return 0;
}

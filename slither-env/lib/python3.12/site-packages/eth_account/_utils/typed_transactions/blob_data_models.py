import hashlib
import os
from typing import (
    List,
    Optional,
    Union,
)

from ckzg import (
    blob_to_kzg_commitment,
    compute_blob_kzg_proof,
    load_trusted_setup,
)
from eth_typing import (
    HexStr,
)
from eth_utils import (
    ValidationError,
)
from hexbytes import (
    HexBytes,
)

# import TRUSTED_SETUP from ./kzg_trusted_setup.txt
TRUSTED_SETUP = os.path.join(
    os.path.dirname(__file__), "blob_transactions", "kzg_trusted_setup.txt"
)
VERSIONED_HASH_VERSION_KZG = b"\x01"


class _BlobDataElement:
    data: Union[HexBytes, bytes]

    def as_hexbytes(self) -> HexBytes:
        return self.data

    def as_bytes(self) -> bytes:
        return bytes(self.data)

    def as_hexstr(self) -> HexStr:
        return HexStr(f"0x{self.as_bytes().hex()}")


class Blob(_BlobDataElement):
    """
    Represents a Blob.
    """

    def __init__(self, data: Union[HexBytes, bytes]) -> None:
        self._validate_blob(data)
        self.data = data

    @staticmethod
    def _validate_blob(v: Union[HexBytes, bytes]) -> None:
        if len(v) != 4096 * 32:
            raise ValidationError(
                "Invalid Blob size. Blob data must be comprised of 4096 32-byte "
                "field elements."
            )


class BlobKZGCommitment(_BlobDataElement):
    """
    Represents a Blob KZG Commitment.
    """

    def __init__(self, data: Union[HexBytes, bytes]) -> None:
        self._validate_commitment(data)
        self.data = data

    @staticmethod
    def _validate_commitment(v: Union[HexBytes, bytes]) -> None:
        if len(v) != 48:
            raise ValidationError("Blob KZG Commitment must be 48 bytes long.")


class BlobProof(_BlobDataElement):
    """
    Represents a Blob Proof.
    """

    def __init__(self, data: Union[HexBytes, bytes]) -> None:
        self._validate_proof(data)
        self.data = data

    @staticmethod
    def _validate_proof(v: Union[HexBytes, bytes]) -> None:
        if len(v) != 48:
            raise ValidationError("Blob Proof must be 48 bytes long.")


class BlobVersionedHash(_BlobDataElement):
    """
    Represents a Blob Versioned Hash.
    """

    def __init__(self, data: Union[HexBytes, bytes]) -> None:
        self._validate_versioned_hash(data)
        self.data = data

    @staticmethod
    def _validate_versioned_hash(v: Union[HexBytes, bytes]) -> None:
        if len(v) != 32:
            raise ValidationError("Blob Versioned Hash must be 32 bytes long.")
        if v[:1] != VERSIONED_HASH_VERSION_KZG:
            raise ValidationError(
                "Blob Versioned Hash must start with the KZG version byte."
            )


class BlobPooledTransactionData:
    """
    Represents the blob data for a type 3 `PooledTransaction` as defined by
    EIP-4844. This class takes blobs as bytes and computes the corresponding
    commitments, proofs, and versioned hashes.
    """

    _versioned_hash_version_kzg: bytes = VERSIONED_HASH_VERSION_KZG
    _versioned_hashes: Optional[List[BlobVersionedHash]] = None
    _commitments: Optional[List[BlobKZGCommitment]] = None
    _proofs: Optional[List[BlobProof]] = None

    blobs: List[Blob]

    def __init__(self, blobs: List[Blob]) -> None:
        self._validate_blobs(blobs)
        self.blobs = blobs

    def _kzg_to_versioned_hash(self, kzg_commitment: BlobKZGCommitment) -> bytes:
        return (
            self._versioned_hash_version_kzg
            + hashlib.sha256(kzg_commitment.data).digest()[1:]
        )

    @staticmethod
    def _validate_blobs(v: List[Blob]) -> None:
        if len(v) == 0:
            raise ValidationError("Blob transactions must contain at least 1 blob.")
        elif len(v) > 6:
            raise ValidationError("Blob transactions cannot contain more than 6 blobs.")

    @property
    def versioned_hashes(self) -> List[BlobVersionedHash]:
        if self._versioned_hashes is None:
            self._versioned_hashes = [
                BlobVersionedHash(
                    data=HexBytes(self._kzg_to_versioned_hash(commitment))
                )
                for commitment in self.commitments
            ]
        return self._versioned_hashes

    @property
    def commitments(self) -> List[BlobKZGCommitment]:
        if self._commitments is None:
            self._commitments = [
                BlobKZGCommitment(
                    data=HexBytes(
                        blob_to_kzg_commitment(
                            blob.data, load_trusted_setup(TRUSTED_SETUP)
                        )
                    )
                )
                for blob in self.blobs
            ]
        return self._commitments

    @property
    def proofs(self) -> List[BlobProof]:
        if self._proofs is None:
            self._proofs = [
                BlobProof(
                    data=HexBytes(
                        compute_blob_kzg_proof(
                            blob.data,
                            commitment.data,
                            load_trusted_setup(TRUSTED_SETUP),
                        )
                    )
                )
                for blob, commitment in zip(self.blobs, self.commitments)
            ]
        return self._proofs

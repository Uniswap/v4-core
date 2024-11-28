from abc import (
    ABC,
    abstractmethod,
)
from typing import (
    Any,
    Dict,
    Optional,
    Tuple,
)

from eth_utils import (
    is_bytes,
    is_string,
    to_bytes,
    to_int,
)
from eth_utils.curried import (
    apply_formatter_to_array,
    apply_formatters_to_dict,
    apply_one_of_formatters,
    hexstr_if_str,
)
from eth_utils.toolz import (
    identity,
    merge,
)

from eth_account._utils.validation import (
    LEGACY_TRANSACTION_FORMATTERS,
)

from .blob_data_models import (
    BlobPooledTransactionData,
)

TYPED_TRANSACTION_FORMATTERS = merge(
    LEGACY_TRANSACTION_FORMATTERS,
    {
        "chainId": hexstr_if_str(to_int),
        "type": hexstr_if_str(to_int),
        "accessList": apply_formatter_to_array(
            apply_formatters_to_dict(
                {
                    "address": apply_one_of_formatters(
                        (
                            (is_string, hexstr_if_str(to_bytes)),
                            (is_bytes, identity),
                        )
                    ),
                    "storageKeys": apply_formatter_to_array(hexstr_if_str(to_int)),
                }
            ),
        ),
        "maxPriorityFeePerGas": hexstr_if_str(to_int),
        "maxFeePerGas": hexstr_if_str(to_int),
        "maxFeePerBlobGas": hexstr_if_str(to_int),
        "blobVersionedHashes": apply_formatter_to_array(hexstr_if_str(to_bytes)),
    },
)


class _TypedTransactionImplementation(ABC):
    """
    Abstract class that every typed transaction must implement.
    Should not be imported or used by clients of the library.
    """

    blob_data: Optional[BlobPooledTransactionData] = None

    @abstractmethod
    def hash(self) -> bytes:
        pass

    @abstractmethod
    def payload(self) -> bytes:
        pass

    @abstractmethod
    def as_dict(self) -> Dict[str, Any]:
        pass

    @abstractmethod
    def vrs(self) -> Tuple[int, int, int]:
        pass

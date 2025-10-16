"""
Embedding service layer using API.
"""

from typing import Dict

from loguru import logger

from api.client import api_client


class EmbeddingService:
    """Service layer for embedding operations using API."""
    
    def __init__(self):
        logger.info("Using API for embedding operations")
    
    def embed_content(self, item_id: str, item_type: str) -> Dict[str, str]:
        """Embed content for vector search."""
        result = api_client.embed_content(item_id=item_id, item_type=item_type)
        return result


# Global service instance
embedding_service = EmbeddingService()
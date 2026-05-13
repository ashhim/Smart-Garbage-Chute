from fastapi import Depends, HTTPException, Header
from jose import jwt, JWTError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.core.config import get_settings
from app.core.rbac import normalize_role
from app.db.session import get_db
from app.models import User

settings = get_settings()

async def get_current_user(authorization: str | None = Header(default=None), db: AsyncSession = Depends(get_db)) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        data = jwt.decode(token, settings.secret_key, algorithms=[settings.jwt_alg])
        email = data.get("sub")
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")
    user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="User account is inactive")
    user.role = normalize_role(user.role)
    return user


def require_roles(*roles: str):
    expected = {normalize_role(role) for role in roles}

    async def dependency(user: User = Depends(get_current_user)) -> User:
        if normalize_role(user.role) not in expected:
            raise HTTPException(
                status_code=403,
                detail="Insufficient privileges for this resource",
            )
        return user

    return dependency
